// Живой прогон ПОЛНОГО ExtractionOrchestrator (не по-клиентно, как в
// e2e_live_test.dart, а ровно так, как это будет делать приложение):
// RemoteConfig.clientPriority -> InnerTubeClient -> PlayerParser ->
// StreamResolver(NodeProcessJsRuntime) -> VideoInfo.
// В конце — Range-чек лучшего стрима.
//
//   dart run tool/e2e_orchestrator.dart [videoId ...]

import 'dart:convert';
import 'dart:io';

import 'package:kmep/kmep.dart';

const _desktopUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

Future<String> httpGetString(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _desktopUA);
    final resp = await req.close();
    return await resp.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

Future<void> main(List<String> args) async {
  // Флаги: --pot-http[=URL] включить BgutilHttpPoTokenProvider
  // (нужен запущенный сервер bgutil; без него бот-чек/SABR на части видео).
  // --pot-js включить BotGuardJsPoTokenProvider (POT целиком в JS-рантайме,
  // без сервера; на десктопе — jsdom-окружение, на устройстве — WebView).
  Uri? potHttpUrl;
  var potJs = false;
  final videos = <String>[];
  for (final a in args) {
    if (a == '--pot-http') {
      potHttpUrl = Uri.parse('http://127.0.0.1:4416');
    } else if (a.startsWith('--pot-http=')) {
      potHttpUrl = Uri.parse(a.substring('--pot-http='.length));
    } else if (a == '--pot-js') {
      potJs = true;
    } else {
      videos.add(a);
    }
  }
  if (videos.isEmpty) {
    videos.addAll(['dQw4w9WgXcQ', 'jNQXAC9IVRw', 'aqz-KE-bpKQ']);
  }

  final jsRuntime = NodeProcessJsRuntime(
      callTimeout: const Duration(seconds: 180));
  final playerJsCache = <String, String>{};

  // POT-провайдер для --pot-js: отдельный рантайм (jsdom на глобале),
  // чтобы не смешивать состояние с player.js-рантаймом резолвера.
  PoTokenProvider? potProvider;
  NodeProcessJsRuntime? bgJsRuntime;
  if (potHttpUrl != null) {
    potProvider = BgutilHttpPoTokenProvider(baseUrl: potHttpUrl);
  } else if (potJs) {
    final bgRuntime = NodeProcessJsRuntime(callTimeout: const Duration(seconds: 180));
    bgJsRuntime = bgRuntime;
    potProvider = BotGuardJsPoTokenProvider(
      jsRuntime: bgRuntime,
      fetchText: httpGetString,
      extraBootstrapParts: () => [
        '''
const _kmepRequire = (typeof require !== 'undefined')
  ? require
  : process.mainModule.require;
const { JSDOM } = _kmepRequire('/tmp/opencode/bgutil/server/node_modules/jsdom');
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
  url: 'https://www.youtube.com/', referrer: 'https://www.youtube.com/',
});
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.location = dom.window.location;
globalThis.origin = dom.window.origin;
if (!Reflect.has(globalThis, 'navigator')) {
  Object.defineProperty(globalThis, 'navigator', { value: dom.window.navigator });
}
''',
      ],
    );
  }

  final orchestrator = ExtractionOrchestrator(
    config: const RemoteConfig(),
    cache: InMemoryCacheManager(),
    streamResolver: StreamResolver(
      jsRuntime: jsRuntime,
      fetchPlayerJs: (url) async {
        if (playerJsCache.containsKey(url)) return playerJsCache[url]!;
        final content = await httpGetString(url);
        playerJsCache[url] = content;
        return content;
      },
    ),
    watchPageMetaProvider: HttpWatchPageMetaProvider(),
    poTokenProvider: potProvider,
  );

  var okCount = 0;
  for (final videoId in videos) {
    stdout.writeln('\n======== $videoId ========');
    try {
      final video = await orchestrator.fetchVideo(videoId);
      KMEPStream? best;
      for (final s in video.streams) {
        if ((s.height ?? -1) > (best?.height ?? -1)) best = s;
      }
      String httpStatus = '-';
      if (best != null) {
        try {
          final client = HttpClient();
          try {
            final req = await client.getUrl(Uri.parse(best.url));
            req.headers.set('Range', 'bytes=0-1023');
            req.headers.set('User-Agent', _desktopUA);
            final resp = await req.close();
            await resp.drain<void>();
            httpStatus = resp.statusCode.toString();
          } finally {
            client.close();
          }
        } catch (_) {}
      }
      final ok = best != null && httpStatus.startsWith('2');
      if (ok) okCount++;
      stdout.writeln('"${video.title}" streams=${video.streams.length} '
          'maxH=${best?.height ?? 0} bestHTTP=$httpStatus ${ok ? 'OK' : 'FAIL'}');
    } on KMEPException catch (e) {
      stdout.writeln('FAIL: [${e.code.name}] ${e.message}');
    } catch (e) {
      stdout.writeln('CRASH: $e');
    }
  }

  stdout.writeln(
      '\nИТОГ: $okCount/${videos.length} через оркестратор '
      '(success rate ${(okCount / videos.length * 100).toStringAsFixed(0)}%)');
  orchestrator.dispose();
  jsRuntime.dispose();
  bgJsRuntime?.dispose();
}
