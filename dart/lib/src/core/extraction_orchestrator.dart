import 'package:http/http.dart' as http;

import '../clients/client_configs.dart';
import '../clients/innertube_client.dart';
import '../models/kmep_models.dart';
import '../parsers/player_parser.dart';
import '../resolvers/stream_resolver.dart';
import 'cache_manager.dart';
import 'po_token.dart';
import 'remote_config.dart';
import 'watch_page_meta.dart';

typedef BackendFallback = Future<VideoInfo> Function(String videoId);

/// Фабрика http-клиента для InnerTube-запросов (инъекция для тестов).
typedef InnerTubeHttpClientFactory = http.Client Function();

/// Центральный диспетчер (EO из спецификации): обходит клиентов по
/// приоритету из RemoteConfig, на каждом шаге пытается получить streams,
/// и только если ВСЕ клиенты пусты/недоступны — падает в backend.
///
/// Cipher-резолв: если клиент отдал форматы с signatureCipher, оркестратор
/// лениво (один раз на видео) достаёт метаданные watch-страницы — STS для
/// browser-клиентов (needsSignatureTimestamp) и player.js URL для
/// StreamResolver — и прогоняет форматы через резолвер. Провайдер может
/// вернуть null (сеть/парс) — тогда клиент с cipher-форматами считается
/// неудачей и идём к следующему по приоритету.
class ExtractionOrchestrator {
  final RemoteConfig config;
  final CacheManager cache;
  final StreamResolver streamResolver;
  final WatchPageMetaProvider? watchPageMetaProvider;
  final PoTokenProvider? poTokenProvider;
  final BackendFallback? backendFallback;
  final InnerTubeHttpClientFactory? httpClientFactory;
  final Map<String, InnerTubeClient> _clients = {};
  final Map<String, WatchPageMeta?> _metaCache = {};
  final Map<String, String?> _poTokenCache = {};

  ExtractionOrchestrator({
    required this.config,
    required this.cache,
    required this.streamResolver,
    this.watchPageMetaProvider,
    this.poTokenProvider,
    this.backendFallback,
    this.httpClientFactory,
  });

  InnerTubeClient _clientFor(String id) => _clients.putIfAbsent(
      id,
      () => InnerTubeClient(ClientRegistry.resolved(id, overrides: config.clientOverrides),
          httpClient: httpClientFactory?.call()));

  Future<WatchPageMeta?> _watchMeta(String videoId) async {
    if (_metaCache.containsKey(videoId)) return _metaCache[videoId];
    final provider = watchPageMetaProvider;
    WatchPageMeta? meta;
    if (provider != null) {
      try {
        meta = await provider.fetch(videoId);
      } catch (_) {
        // Провайдер не обязан быть надёжным: нет meta -> STS/player.js нет,
        // соответствующие клиенты отработают как неудачные.
        meta = null;
      }
    }
    _metaCache[videoId] = meta;
    return meta;
  }

  /// Токен запрашивается один раз на видео. Провайдер сам решает, для каких
  /// видео имеет смысл выдавать токен; может кинуть — трактуем как null.
  Future<String?> _poToken(String videoId) async {
    if (_poTokenCache.containsKey(videoId)) return _poTokenCache[videoId];
    String? token;
    final provider = poTokenProvider;
    if (provider != null) {
      try {
        token = await provider.tokenFor(videoId);
      } catch (_) {
        token = null;
      }
    }
    _poTokenCache[videoId] = token;
    return token;
  }

  Future<VideoInfo> fetchVideo(String videoId) async {
    final cached = await cache.getVideo(videoId);
    if (cached != null) return cached;

    VideoInfo? best;
    final errors = <String, KMEPException>{};

    for (final clientId in config.clientPriority) {
      if (config.emergencyMode) break;

      for (var attempt = 0; attempt <= config.maxRetriesPerClient; attempt++) {
        try {
          final clientConfig =
              ClientRegistry.resolved(clientId, overrides: config.clientOverrides);
          final client = _clientFor(clientId);

          // PO token: нужен requiresPoToken-клиентам (IOS/WEB на части IP).
          final poToken = clientConfig.requiresPoToken ? await _poToken(videoId) : null;

          // STS и visitorData берутся из watch-страницы один раз на видео.
          // STS нужен browser-клиентам, visitorData — TVHTML5 (needsVisitorData).
          int? sts;
          String? visitorData;
          if (clientConfig.needsSignatureTimestamp ||
              clientConfig.needsVisitorData) {
            final meta = await _watchMeta(videoId);
            sts = clientConfig.needsSignatureTimestamp ? meta?.signatureTimestamp : null;
            visitorData = clientConfig.needsVisitorData ? meta?.visitorData : null;
          }
          final raw = await client.fetchPlayer(
            videoId,
            poToken: poToken,
            signatureTimestamp: sts,
            visitorData: visitorData,
          );
          var video = PlayerParser.parse(raw, fallbackVideoId: videoId);

          final rawFormats = PlayerParser.rawFormats(raw);
          // Резолв нужен в двух случаях:
          //   1) cipher-формат (signatureCipher) — дешифровка + n;
          //   2) ПРЯМОЙ url с параметром n — WEB+POT отдаёт именно такие
          //      (itag18 с сырым n): без трансформации CDN отвечает 403.
          //      Это дало 74% отказов в метриках 2026-08-22, пока условие
          //      покрывало только cipher.
          final needsCipherResolve = rawFormats.any((f) {
            final url = f['url'] as String?;
            if (url == null) {
              return f['signatureCipher'] != null || f['cipher'] != null;
            }
            return Uri.parse(url).queryParameters.containsKey('n');
          });

          if (needsCipherResolve && !video.isLive) {
            final meta = await _watchMeta(videoId);
            final playerJsUrl = meta?.playerJsUrl;
            if (playerJsUrl != null) {
              final resolvedStreams =
                  await streamResolver.resolve(rawFormats, playerJsUrl: playerJsUrl);
              video = _withStreams(video, _applyPoToken(resolvedStreams, poToken));
            }
            // playerJsUrl == null -> остаётся сырой парс (пустые url у
            // cipher-форматов), ниже сработает "No streams" и фолбэк.
          } else if (!video.isLive) {
            video = _withStreams(video, _applyPoToken(video.streams, poToken));
          }

          if (video.streams.isEmpty && video.hlsManifestUrl == null) {
            throw KMEPException(KMEPErrorCode.partial, 'No streams from $clientId', clientId: clientId);
          }

          if (best == null || _isBetter(video, best)) best = video;
          if (_meetsTarget(best)) {
            await cache.putVideo(videoId, best);
            return best;
          }
          break;
        } on KMEPException catch (e) {
          errors[clientId] = e;
          if (e.code == KMEPErrorCode.rateLimited) {
            await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
            continue;
          }
          break;
        }
      }
    }

    if (best != null) {
      await cache.putVideo(videoId, best);
      return best;
    }

    if (config.enableEmbeddedYtdlp && backendFallback != null) {
      try {
        final video = await backendFallback!(videoId);
        await cache.putVideo(videoId, video);
        return video;
      } catch (e) {
        throw KMEPException(KMEPErrorCode.unavailable, 'All clients and backend failed: $errors / $e');
      }
    }

    throw KMEPException(KMEPErrorCode.unavailable, 'All extraction methods exhausted: $errors');
  }

  /// Добавляет pot= к googlevideo-URL, если токен есть. Для не-gv хостов
  /// (HLS-плейлисты и пр.) токен не предназначен — не трогаем.
  List<KMEPStream> _applyPoToken(List<KMEPStream> streams, String? poToken) {
    if (poToken == null || poToken.isEmpty) return streams;
    return [
      for (final s in streams)
        s.url.contains('googlevideo.com/')
            ? KMEPStream(
                url: '${s.url}${s.url.contains('?') ? '&' : '?'}pot=$poToken',
                quality: s.quality,
                codec: s.codec,
                type: s.type,
                itag: s.itag,
                width: s.width,
                height: s.height,
                bitrate: s.bitrate,
                mimeType: s.mimeType,
                isLive: s.isLive,
              )
            : s
    ];
  }

  bool _meetsTarget(VideoInfo v) {
    if (v.isLive) return v.hlsManifestUrl != null;
    final maxHeight = v.streams.map((s) => s.height ?? 0).fold(0, (a, b) => a > b ? a : b);
    return maxHeight >= config.targetMinHeight;
  }

  bool _isBetter(VideoInfo a, VideoInfo b) {
    int maxH(VideoInfo v) => v.streams.map((s) => s.height ?? 0).fold(0, (x, y) => x > y ? x : y);
    return maxH(a) > maxH(b);
  }

  VideoInfo _withStreams(VideoInfo v, List<KMEPStream> streams) => VideoInfo(
        videoId: v.videoId,
        title: v.title,
        description: v.description,
        durationSeconds: v.durationSeconds,
        viewCount: v.viewCount,
        publishDate: v.publishDate,
        channelId: v.channelId,
        channelName: v.channelName,
        channelAvatar: v.channelAvatar,
        thumbnails: v.thumbnails,
        tags: v.tags,
        category: v.category,
        isLive: v.isLive,
        streams: streams,
        hlsManifestUrl: v.hlsManifestUrl,
      );

  void dispose() {
    for (final c in _clients.values) {
      c.close();
    }
  }
}
