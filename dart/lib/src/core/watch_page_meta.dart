import 'dart:convert';
import 'dart:io';

/// Метаданные watch-страницы, нужные для cipher-резолва и сессионных
/// полей: signatureTimestamp (STS) для browser-клиентов, URL player.js
/// для StreamResolver, visitorData (ytcfg VISITOR_DATA) для клиентов,
/// которым она требуется (TV; та же строка потом привязывает PO token).
class WatchPageMeta {
  final int? signatureTimestamp;
  final String? playerJsUrl;
  final String? visitorData;
  const WatchPageMeta({this.signatureTimestamp, this.playerJsUrl, this.visitorData});
}

/// Абстракция над получением WatchPageMeta — оркестратор зависит только
/// от неё, чтобы оставаться тестируемым без сети.
abstract class WatchPageMetaProvider {
  Future<WatchPageMeta?> fetch(String videoId);
}

/// Реальная реализация через GET watch-страницы.
///
/// Регэкспы те же, что в tool/e2e_live_test.dart — держим синхронно.
/// Любая ошибка сети/парса -> null (оркестратор продолжит без meta,
/// cipher-форматы в этом случае не резолвятся и клиент считается неудачей).
class HttpWatchPageMetaProvider implements WatchPageMetaProvider {
  final String watchUrlTemplate;
  final Duration timeout;

  HttpWatchPageMetaProvider({
    this.watchUrlTemplate = 'https://www.youtube.com/watch?v=%s&hl=en&gl=US',
    this.timeout = const Duration(seconds: 8),
  });

  @override
  Future<WatchPageMeta?> fetch(String videoId) async {
    try {
      final client = HttpClient();
      try {
        final req = await client
            .getUrl(Uri.parse(watchUrlTemplate.replaceAll('%s', videoId)))
            .timeout(timeout);
        req.headers.set('User-Agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36');
        final resp = await req.close().timeout(timeout);
        final html = await resp.transform(utf8.decoder).join().timeout(timeout);

        final stsStr =
            RegExp(r'"STS":(\d+)').firstMatch(html)?.group(1);
        String? jsUrl;
        final m = RegExp(r'"jsUrl":"([^"]+base\.js)"').firstMatch(html) ??
            RegExp(r'src="(/s/player/[^"]+base\.js)"').firstMatch(html);
        if (m != null) {
          final p = m.group(1)!.replaceAll(r'\/', '/');
          jsUrl = p.startsWith('http') ? p : 'https://www.youtube.com$p';
        }
        // ytcfg VISITOR_DATA — JSON-строка с экранированием, раскодируем.
        String? visitorData;
        final vdRaw = RegExp(r'"VISITOR_DATA":"((?:[^"\\]|\\.)*)"').firstMatch(html)?.group(1);
        if (vdRaw != null) {
          try {
            visitorData = jsonDecode('"$vdRaw"') as String;
          } catch (_) {}
        }
        return WatchPageMeta(
          signatureTimestamp: stsStr == null ? null : int.parse(stsStr),
          playerJsUrl: jsUrl,
          visitorData: visitorData,
        );
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }
}

/// Память на видео: watch-страница стабильна часами, а за одно извлечение
/// к ней могут обратиться и оркестратор (STS/visitor), и POT-биндинг —
/// качаем один раз. Пусть провайдер кэширует сам, тогда один инстанс
/// можно смело шарить между оркестратором и bindingFor.
class CachedWatchPageMetaProvider implements WatchPageMetaProvider {
  final WatchPageMetaProvider inner;
  final Map<String, WatchPageMeta?> _cache = {};
  final int maxEntries;

  CachedWatchPageMetaProvider(this.inner, {this.maxEntries = 100});

  @override
  Future<WatchPageMeta?> fetch(String videoId) async {
    if (_cache.containsKey(videoId)) return _cache[videoId];
    final meta = await inner.fetch(videoId);
    if (_cache.length >= maxEntries) _cache.clear();
    _cache[videoId] = meta;
    return meta;
  }
}
