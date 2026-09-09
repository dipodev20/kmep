// ЖИВОЙ e2e-тест всего Dart-пайплайна KMEP на реальном YouTube:
//   watch-страница (STS + player.js URL)
//     -> InnerTubeClient по каждому клиенту реестра
//     -> PlayerParser
//     -> StreamResolver (NodeProcessJsRuntime: шим + player.js + discovery)
//     -> Range-чек итогового URL лучшего стрима
//
//   dart run tool/e2e_live_test.dart [videoId ...]
//
// Метрики в конце: success rate по клиентам и путь решения (с JS / без JS).

import 'dart:convert';
import 'dart:io';

import 'package:kmep/kmep.dart';

const desktopUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';
const defaultVideos = ['dQw4w9WgXcQ', 'jNQXAC9IVRw', 'aqz-KE-bpKQ'];
const clientsToTest = ['ANDROID_VR', 'WEB', 'IOS', 'TV'];

Future<String> httpGet(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', desktopUA);
    final resp = await req.close();
    return await resp.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

/// Range bytes=0-1023 -> HTTP статус строкой.
Future<String> rangeCheck(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('Range', 'bytes=0-1023');
    req.headers.set('User-Agent', desktopUA);
    final resp = await req.close();
    await resp.drain<void>();
    return resp.statusCode.toString();
  } finally {
    client.close();
  }
}

class WatchMeta {
  final int? signatureTimestamp;
  final String? playerJsUrl;
  WatchMeta(this.signatureTimestamp, this.playerJsUrl);
}

Future<WatchMeta> fetchWatchMeta(String videoId) async {
  final html = await httpGet('https://www.youtube.com/watch?v=$videoId&hl=en&gl=US');
  final sts = RegExp(r'"STS":(\d+)').firstMatch(html)?.group(1);
  String? jsUrl;
  final m = RegExp(r'"jsUrl":"([^"]+base\.js)"').firstMatch(html) ??
      RegExp(r'src="(/s/player/[^"]+base\.js)"').firstMatch(html);
  if (m != null) {
    final p = m.group(1)!.replaceAll(r'\/', '/');
    jsUrl = p.startsWith('http') ? p : 'https://www.youtube.com$p';
  }
  return WatchMeta(sts == null ? null : int.parse(sts), jsUrl);
}

class Row {
  final String clientId;
  final String status;
  final int formats;
  final int directFormats;
  final int resolvedFormats;
  final int maxHeight;
  final String bestHttp;
  final String note;
  Row(this.clientId, this.status, this.formats, this.directFormats,
      this.resolvedFormats, this.maxHeight, this.bestHttp,
      [this.note = '']);
  bool get ok => resolvedFormats > 0 && bestHttp.startsWith('2');
  bool get solvedWithoutJs => resolvedFormats > 0 && directFormats == formats;
}

int maxHeightOf(List<Map<String, dynamic>> formats) {
  var m = 0;
  for (final f in formats) {
    final h = (f['height'] as num?)?.toInt() ?? 0;
    if (h > m) m = h;
  }
  return m;
}

Future<void> main(List<String> args) async {
  final videos = args.isEmpty ? defaultVideos : args;

  // player.js качается один раз на URL за весь прогон.
  final playerJsCache = <String, String>{};
  Future<String?> Function() loadPlayerJs(String? url) => () async {
        if (url == null) return null;
        if (playerJsCache.containsKey(url)) return playerJsCache[url]!;
        final content = await httpGet(url);
        playerJsCache[url] = content;
        return content;
      };

  final rows = <Row>[];

  for (final videoId in videos) {
    stdout.writeln('\n======== $videoId ========');
    final meta = await fetchWatchMeta(videoId);
    stdout.writeln(
        'watch: STS=${meta.signatureTimestamp}, playerJs=${meta.playerJsUrl ?? 'НЕ НАЙДЕН'}');

    for (final clientId in clientsToTest) {
      final config = ClientRegistry.byId(clientId);
      final row = config.id == clientId
          ? await _testClient(config, videoId, meta, loadPlayerJs(meta.playerJsUrl))
          : Row(clientId, 'нет в реестре', 0, 0, 0, 0, '-');
      rows.add(row);
      stdout.writeln(
          '[${row.clientId}] status=${row.status} форматов=${row.formats} '
          '(прямых=${row.directFormats}) решено=${row.resolvedFormats} '
          'maxH=${row.maxHeight} bestHTTP=${row.bestHttp}'
          '${row.note.isEmpty ? '' : ' | ${row.note}'}');
    }
  }

  stdout.writeln('\n======== ИТОГИ ========');
  for (final id in clientsToTest) {
    final sub = rows.where((r) => r.clientId == id).toList();
    if (sub.isEmpty) continue;
    final okCount = sub.where((r) => r.ok).length;
    final noJs = sub.where((r) => r.solvedWithoutJs).length;
    stdout.writeln('$id: $okCount/${sub.length} успешно '
        '(success rate ${(okCount / sub.length * 100).toStringAsFixed(0)}%, '
        'без JS: $noJs)');
  }
}

Future<Row> _testClient(
  InnerTubeClientConfig config,
  String videoId,
  WatchMeta meta,
  Future<String?> Function() loadPlayerJs,
) async {
  final client = InnerTubeClient(config);
  try {
    final raw = await client.fetchPlayer(
      videoId,
      signatureTimestamp:
          config.id == 'WEB' || config.id == 'TV' ? meta.signatureTimestamp : null,
    );
    final status = raw['playabilityStatus']?['status']?.toString() ?? '?';
    final reason = raw['playabilityStatus']?['reason']?.toString() ?? '';
    final rawFormats = PlayerParser.rawFormats(raw);
    final direct = rawFormats.where((f) => f['url'] != null).length;

    final hasCipher = rawFormats.any((f) =>
        f['url'] == null &&
        (f['signatureCipher'] != null || f['cipher'] != null));
    // Прямые url с сырым n тоже требуют резолва (WEB+POT отдаёт такие).
    final directNeedsN = rawFormats.any((f) =>
        f['url'] != null &&
        Uri.parse(f['url'] as String).queryParameters.containsKey('n'));
    final sabrOnly = rawFormats.where((f) =>
        f['url'] == null &&
        f['signatureCipher'] == null &&
        f['cipher'] == null).length;
    final directList =
        rawFormats.where((f) => f['url'] != null).toList();

    var resolved = const <KMEPStream>[];
    var note = '';

    if (rawFormats.isEmpty) {
      note = reason;
    } else if (!hasCipher && !directNeedsN) {
      // Прямые url — резолвер не нужен. SABR-дескрипторы (без url) здесь
      // же просто не попадают в resolved.
      resolved = directList.map((f) {
        final mime = f['mimeType']?.toString() ?? '';
        return KMEPStream(
          url: f['url'] as String,
          quality: f['qualityLabel']?.toString() ?? 'audio',
          codec: 'n/a',
          type: mime.startsWith('audio/') ? 'audio' : 'video',
          itag: (f['itag'] as num?)?.toInt() ?? 0,
          height: (f['height'] as num?)?.toInt(),
          mimeType: mime,
        );
      }).toList();
      note = directList.isEmpty
          ? 'только SABR-дескрипторы ($sabrOnly)'
          : 'без JS';
    } else {
      final playerJs = await loadPlayerJs();
      if (playerJs == null) {
        return Row(config.id, status, rawFormats.length, direct, 0,
            maxHeightOf(rawFormats), '-', 'нет player.js URL');
      }
      final jsRuntime = NodeProcessJsRuntime();
      final resolver = StreamResolver(
        jsRuntime: jsRuntime,
        fetchPlayerJs: (_) async => playerJs,
      );
      try {
        resolved = await resolver.resolve(rawFormats, playerJsUrl: 'cached');
        note = sabrOnly > 0 ? 'через player.js (SABR-дескрипторов: $sabrOnly)' : 'через player.js';
      } on KMEPException catch (e) {
        note = 'resolver: ${e.message}';
      } finally {
        jsRuntime.dispose();
      }
    }

    KMEPStream? best;
    for (final s in resolved) {
      if ((s.height ?? -1) > (best?.height ?? -1)) best = s;
    }
    final bestHttp =
        best == null ? '-' : await rangeCheck(best.url).catchError((e) => 'ERR');

    return Row(config.id, status, rawFormats.length, direct, resolved.length,
        maxHeightOf(rawFormats), bestHttp, note);
  } on KMEPException catch (e) {
    return Row(config.id, 'FAIL(${e.code.name})', 0, 0, 0, 0, '-', e.message);
  } catch (e, st) {
    return Row(config.id, 'CRASH', 0, 0, 0, 0, '-',
        '$e\n${st.toString().split('\n').take(4).join('\n')}');
  } finally {
    client.close();
  }
}
