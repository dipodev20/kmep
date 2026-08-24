// ЖИВОЙ e2e BotGuardJsPoTokenProvider: полный цикл on-device POT без
// сервера bgutil, на десктопе через NodeProcessJsRuntime + jsdom
// (воспроизведение окружения из pot_research/bg_full2.js, R1/R2).
//
// Проверяет НАШУ реализацию (не референс): homepage -> челлендж ->
// интерпретатор в JS -> snapshot -> GenerateIT -> минтинг, затем живую
// сверку на WEB-клиенте: без POT / POT(visitorData) / POT(videoId).
//
//   dart run tool/pot_bg_e2e.dart [videoId ...]

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:kmep_proto/kmep.dart';

const _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

Future<String> _fetchText(String url) async {
  final resp = await http.get(Uri.parse(url), headers: const {
    'User-Agent': _ua,
    'Accept': '*/*',
    'Accept-Language': 'en-US,en;q=0.7',
  }).timeout(const Duration(seconds: 30));
  if (resp.statusCode != 200) {
    throw KMEPException(KMEPErrorCode.networkError,
        'GET $url -> HTTP ${resp.statusCode}');
  }
  return resp.body;
}

/// jsdom-окружение внутри JS-контекста (как у bgutil): настоящий DOM,
/// который BotGuard скорит положительно (R3). Только для десктопа;
/// на устройстве WebView даёт всё это нативно.
const _jsdomPart = r'''
globalThis.__req = process.mainModule.require;
var __JSDOM = __req('/tmp/opencode/bgutil/server/node_modules/jsdom').JSDOM;
var __dom = new __JSDOM('<!DOCTYPE html><html lang="en"><head><title></title></head><body></body></html>', {
  url: 'https://www.youtube.com/',
  referrer: 'https://www.youtube.com/',
});
globalThis.window = __dom.window;
globalThis.document = __dom.window.document;
globalThis.location = __dom.window.location;
globalThis.origin = __dom.window.origin;
if (!Reflect.has(globalThis, 'navigator')) {
  Object.defineProperty(globalThis, 'navigator', { value: __dom.window.navigator });
}
''';

Future<void> main(List<String> args) async {
  final videos = args.isNotEmpty ? args : ['jNQXAC9IVRw'];
  final t0 = Stopwatch()..start();
  final runtime = NodeProcessJsRuntime(callTimeout: const Duration(seconds: 120));
  final resolverRuntime =
      NodeProcessJsRuntime(callTimeout: const Duration(seconds: 120));
  final playerJsCache = <String, String>{};
  final resolver = StreamResolver(
    jsRuntime: resolverRuntime,
    fetchPlayerJs: (url) async {
      final cached = playerJsCache[url];
      if (cached != null) return cached;
      final body = await _fetchText(url);
      return playerJsCache[url] = body;
    },
  );

  final provider = BotGuardJsPoTokenProvider(
    jsRuntime: runtime,
    fetchText: _fetchText,
    extraBootstrapParts: () => [_jsdomPart],
    stepTimeout: const Duration(seconds: 40),
  );

  // --- Цикл провайдера: биндинг videoId ---
  final sw = Stopwatch()..start();
  final potVid = await provider.tokenFor(videos.first);
  stdout.writeln(
      '[${sw.elapsedMilliseconds} ms] tokenFor(${videos.first}) -> '
      '${potVid == null ? "NULL (${provider.lastError})" : "${potVid.length} симв."}');

  // Второй вызов должен пойти по кэшу минтера (без нового GenerateIT).
  sw.reset();
  final potVidCached = await provider.tokenFor(videos.first);
  stdout.writeln('[${sw.elapsedMilliseconds} ms] повторный вызов -> '
      '${potVidCached != null && potVidCached == potVid ? "из кэша OK" : "НЕ из кэша!"}');

  if (potVid == null) {
    stdout.writeln('ПАЙПЛАЙН СЛОМАН — дальше смысла нет');
    exit(1);
  }

  // --- Живая сверка на WEB-клиенте ---
  var passCount = 0, totalChecks = 0;
  for (final videoId in videos) {
    stdout.writeln('\n===== $videoId =====');
    final meta = await HttpWatchPageMetaProvider().fetch(videoId);
    final sts = meta?.signatureTimestamp;
    final watchVd = meta?.visitorData;

    // POT с биндингом visitorData этой страницы (для WEB без эксперимента).
    final potForVideoBinding = videos.contains(videoId)
        ? await provider.tokenFor(videoId)
        : null;

    Future<void> check(String label, String? pot, String? vd) async {
      totalChecks++;
      try {
        final client = InnerTubeClient(ClientRegistry.resolved('WEB'));
        final raw = await client.fetchPlayer(
          videoId,
          poToken: pot,
          signatureTimestamp: sts,
          visitorData: vd,
        );
        client.close();
        final status =
            (raw['playabilityStatus']?['status'] ?? '?').toString();
        final reason = raw['playabilityStatus']?['reason'];
        final formats = PlayerParser.rawFormats(raw);
        final direct = formats.where((f) => f['url'] != null).length;
        final cipher = formats.where((f) =>
            f['signatureCipher'] != null || f['cipher'] != null).length;
        stdout.writeln('[$label] status=$status форматов=${formats.length} '
            '(прямых=$direct cipher=$cipher sabr=${formats.length - direct - cipher})'
            '${reason != null ? " :: ${"$reason".characters.take(60)}" : ""}');

        // Range-чек первого прямого URL с pot= и без.
        String? url;
        var resolvable = formats.where((f) =>
            f['signatureCipher'] != null ||
            f['cipher'] != null ||
            (f['url'] != null &&
                Uri.parse(f['url'] as String)
                    .queryParameters
                    .containsKey('n'))).toList();
        if (resolvable.isNotEmpty && meta?.playerJsUrl != null && pot != null) {
          // Полный прод-путь: cipher/n через player.js (n-трансформация).
          final streams = await resolver.resolve(formats,
              playerJsUrl: meta!.playerJsUrl!);
          url = streams.isEmpty ? null : streams.first.url;
          if (url == null) {
            stdout.writeln('[$label] resolve дал 0 стримов');
          }
        } else {
          for (final f in formats) {
            final u = f['url'] as String?;
            if (u != null) {
              url = u;
              break;
            }
          }
        }
        if (url != null) {
          Future<String> range(String u) async {
            try {
              final r = await http.get(Uri.parse(u),
                  headers: const {'Range': 'bytes=0-1023', 'User-Agent': _ua});
              return '${r.statusCode}';
            } catch (e) {
              return 'ERR';
            }
          }

          final noPot = await range(url);
          final withPot = pot == null ? '-' : await range('$url&pot=$pot');
          final ok = withPot.startsWith('2') || noPot.startsWith('2');
          if (ok) passCount++;
          stdout.writeln('[$label] Range без pot=: $noPot | c pot=: $withPot'
              ' -> ${ok ? "PASS" : "FAIL"}');
        } else {
          final ok = status == 'OK';
          if (ok) passCount++;
          stdout.writeln('[$label] прямых URL нет -> по статусу: '
              '${ok ? "PASS" : "FAIL"}');
        }
      } catch (e) {
        stdout.writeln('[$label] CRASH: $e');
      }
    }

    await check('БЕЗ POT', null, null);
    await check('POT(videoId)', potForVideoBinding ?? potVid, null);
    if (watchVd != null) {
      // Токен под другой биндинг не перегенерируем — gvs-путь основной;
      // visitorData-биндинг проверяем только если он совпадает с уже
      // выпущенным (homepage vd).
      await check('POT(videoId)+vd-заголовок', potForVideoBinding, watchVd);
    }
  }

  stdout.writeln('\nИТОГ: $passCount/$totalChecks проверок PASS, '
      'полное время ${(t0.elapsedMilliseconds / 1000).toStringAsFixed(1)} c');
  runtime.dispose();
  exit(passCount > 0 ? 0 : 1);
}

extension on String {
  Iterable<String> get characters => split('');
}
