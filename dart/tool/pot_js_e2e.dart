// ЖИВАЯ проверка BotGuardJsPoTokenProvider на десктопе через ПРОДАКШЕН-ФОРМУ:
// NodeProcessJsRuntime + jsdom-окружение (extraBootstrapParts) -> полный
// цикл BotGuard -> реальный POT -> WEB player запрос с токеном ->
// резолв cipher через StreamResolver (второй рантайм, прод-путь) ->
// Range-чек с pot= и без.
//
// Доказательная база: docs/AGENT_HANDOFF.md, раздел «on-device POT» (R1/R2).
//
//   dart run tool/pot_js_e2e.dart [videoId]
//
// Ожидание: POT выдан (после R2 валиден на стороне Google); player status=OK;
// Range-сравнение информативно только на гейтящемся IP (см. R5).

import 'dart:convert';
import 'dart:io';

import 'package:kmep_proto/kmep.dart';

const _desktopUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

/// Путь к установленному jsdom (десктопная диагностика, не прод).
const _jsdomPath =
    '/tmp/opencode/bgutil/server/node_modules/jsdom';

/// JS-часть окружения для десктопного прогона: jsdom на глобале child-
/// процесса. В WebViewJsRuntime (прод) этот часть НЕ нужна — там настоящие
/// window/document/navigator.
String jsdomEnvPart() => '''
// Часть грузится через (0,eval) в глобал-скоупе child-процесса, где
// require недоступен (это локал модуля) — достаём через mainModule.
const _kmepRequire = (typeof require !== 'undefined')
  ? require
  : process.mainModule.require;
const { JSDOM } = _kmepRequire(${jsonEncode(_jsdomPath)});
const dom = new JSDOM('<!DOCTYPE html><html lang="en"><head><title></title></head><body></body></html>', {
  url: 'https://www.youtube.com/',
  referrer: 'https://www.youtube.com/',
});
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.location = dom.window.location;
globalThis.origin = dom.window.origin;
if (!Reflect.has(globalThis, 'navigator')) {
  Object.defineProperty(globalThis, 'navigator', { value: dom.window.navigator });
}
''';

Future<String> httpGetString(String url,
    {Map<String, String> headers = const {}}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _desktopUA);
    headers.forEach(req.headers.set);
    final resp = await req.close();
    if (resp.statusCode >= 300 && resp.statusCode < 400 && resp.headers.value('location') != null) {
      final location = resp.headers.value('location')!;
      await resp.drain<void>();
      return await httpGetString(location, headers: headers);
    }
    return await resp.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

Future<String?> _rangeStatus(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('Range', 'bytes=0-1023');
    req.headers.set('User-Agent', _desktopUA);
    final resp = await req.close();
    await resp.drain<void>();
    return resp.statusCode.toString();
  } catch (e) {
    return 'ERR:$e';
  } finally {
    client.close();
  }
}

Future<void> main(List<String> args) async {
  final videoId = args.isNotEmpty ? args.first : 'dQw4w9WgXcQ';
  stdout.writeln('== POT через продакшен-форму (BotGuardJsPoTokenProvider) ==');

  // --- 1. Провайдер ---
  // ВАЖНО: на ARM-девайсах require(jsdom)+JSDOM занимает до 40 с —
  // callTimeout должен покрывать это (кэш require действует внутри
  // одного child-процесса).
  final bgRuntime = NodeProcessJsRuntime(callTimeout: const Duration(seconds: 180));
  final provider = BotGuardJsPoTokenProvider(
    jsRuntime: bgRuntime,
    fetchText: (url) => httpGetString(url),
    extraBootstrapParts: () => [jsdomEnvPart()],
    homepageTimeout: const Duration(seconds: 30),
    stepTimeout: const Duration(seconds: 60),
  );

  final sw = Stopwatch()..start();
  final pot = await provider.tokenFor(videoId);
  sw.stop();
  if (pot == null) {
    stdout.writeln('FAIL: POT не выдан, lastError=${provider.lastError}');
    bgRuntime.dispose();
    exit(1);
  }
  stdout.writeln('[${sw.elapsedMilliseconds} ms] POT(videoId-биндинг): '
      '${pot.length} симв: ${pot.substring(0, pot.length > 32 ? 32 : pot.length)}...');

  // Маржинальная стоимость второго токена (кэш сессии): должен быть ~мс.
  final t2videoId = args.length > 1 ? args[1] : 'jNQXAC9IVRw';
  sw.reset();
  final pot2 = await provider.tokenFor(t2videoId);
  sw.stop();
  stdout.writeln('[${sw.elapsedMilliseconds} ms] POT("$t2videoId") из той же сессии: '
      '${pot2 != null ? "ok (${pot2.length} симв)" : "FAIL: ${provider.lastError}"}');

  // --- 2. Watch-мета для WEB-запроса ---
  final watchHtml = await httpGetString(
      'https://www.youtube.com/watch?v=$videoId&hl=en&gl=US');
  final vdMatch =
      RegExp(r'"VISITOR_DATA":"((?:[^"\\]|\\.)*)"').firstMatch(watchHtml);
  final watchVd = vdMatch != null
      ? jsonDecode('"${vdMatch.group(1)}"') as String
      : null;
  final sts = int.parse(
      RegExp(r'"STS":(\d+)').firstMatch(watchHtml)?.group(1) ?? '0');
  stdout.writeln('watch-мета: sts=$sts, visitorData=${watchVd?.substring(0, 12)}...');

  // --- 3. WEB player запрос с токеном (serviceIntegrityDimensions) ---
  Future<Map<String, dynamic>> playerReq(String? potParam) async {
    final body = jsonEncode({
      'videoId': videoId,
      'context': {
        'client': {
          'clientName': 'WEB',
          'clientVersion': '2.20240808.00.00',
          'hl': 'en',
          'gl': 'US',
          if (watchVd != null) 'visitorData': watchVd,
        }
      },
      'contentCheckOk': true,
      'racyCheckOk': true,
      'playbackContext': {'contentPlaybackContext': {'signatureTimestamp': sts}},
      'serviceIntegrityDimensions': {'poToken': potParam},
    });
    final client = HttpClient();
    try {
      final req = await client
          .postUrl(Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'));
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('User-Agent', _desktopUA);
      req.headers.set('X-YouTube-Client-Name', '1');
      req.headers.set('X-YouTube-Client-Version', '2.20240808.00.00');
      req.headers.set('Origin', 'https://www.youtube.com');
      if (watchVd != null) req.headers.set('X-Goog-Visitor-Id', watchVd);
      req.write(body);
      final resp = await req.close();
      return jsonDecode(await resp.transform(utf8.decoder).join())
          as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  final j = await playerReq(pot);
  final status = j['playabilityStatus']?['status'];
  final formats = <Map<String, dynamic>>[
    ...?(j['streamingData']?['formats'] as List?)
        ?.cast<Map<String, dynamic>>(),
    ...?(j['streamingData']?['adaptiveFormats'] as List?)
        ?.cast<Map<String, dynamic>>(),
  ];
  final direct = formats.where((f) => f['url'] != null).length;
  final ciphers = formats
      .where((f) => f['signatureCipher'] != null || f['cipher'] != null)
      .length;
  stdout.writeln('player+POT: status=$status форматов=${formats.length} '
      '(прямых=$direct, cipher=$ciphers, sabr=${formats.length - direct - ciphers})');

  // --- 4. Резолв первого cipher через StreamResolver (ПРОД-путь) ---
  String? resolved;
  final cipherFmt = formats.firstWhere(
      (f) => f['signatureCipher'] != null || f['cipher'] != null,
      orElse: () => <String, dynamic>{});
  if (cipherFmt.isNotEmpty) {
    // playerJsUrl — из watch-меты, как в оркестраторе (assets в свежих
    // playerResponse может отсутствовать).
    final meta = await HttpWatchPageMetaProvider().fetch(videoId);
    final playerJsUrl = meta?.playerJsUrl;
    if (playerJsUrl == null) {
      stdout.writeln('playerJsUrl не найден в watch-странице');
    } else {
    final resolverRuntime = NodeProcessJsRuntime(callTimeout: const Duration(seconds: 180));
    final playerJsCache = <String, String>{};
    final resolver = StreamResolver(
      jsRuntime: resolverRuntime,
      fetchPlayerJs: (url) async {
        if (playerJsCache.containsKey(url)) return playerJsCache[url]!;
        final content = await httpGetString(url);
        playerJsCache[url] = content;
        return content;
      },
    );
    try {
      final streams = await resolver.resolve(
          formats.cast<Map<String, dynamic>>(),
          playerJsUrl: playerJsUrl);
      stdout.writeln('StreamResolver: ${streams.length} стримов разрешено');
      resolved = streams.first.url;
    } on KMEPException catch (e) {
      stdout.writeln('StreamResolver FAIL: [${e.code.name}] ${e.message}');
    } finally {
      resolverRuntime.dispose();
    }
    }
  } else if (direct > 0) {
    resolved = (formats.firstWhere((f) => f['url'] != null))['url'] as String;
  }

  // --- 5. Range-сравнение ---
  if (resolved != null) {
    final noPot = await _rangeStatus(resolved);
    final withPot = await _rangeStatus('$resolved&pot=$pot');
    final informative = (noPot ?? '').startsWith('4')
        ? 'информативно (IP гейтится)'
        : 'НЕинформативно: IP не гейтится даже без pot= (см. R5)';
    stdout.writeln('Range без pot=: $noPot | с pot=: $withPot -> $informative');
  } else {
    stdout.writeln('Range-чек невозможен: ни cipher, ни прямых URL нет '
        '(SABR-only ответ; POT сегодня не превращает их в прямые URL)');
  }

  stdout.writeln('\nlastError=${provider.lastError}');
  bgRuntime.dispose();
}
