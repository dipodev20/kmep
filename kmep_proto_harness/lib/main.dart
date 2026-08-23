// On-device smoke test для FlutterJsRuntime + ANDROID_VR baseline.
//
// Экран -> кнопка "Run on-device test" -> пошаговый лог ПРЯМО НА ЭКРАНЕ
// (APK ставится вручную, живой консоли может не быть). Любое исключение
// печатается целиком, со стеком — это и есть диагностика.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'package:kmep_proto/kmep.dart';
import 'webview_js_runtime.dart';

const _desktopUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

bool _hasSource(Map<String, dynamic> f) =>
    f['url'] != null || f['signatureCipher'] != null || f['cipher'] != null;

/// Формат требует вызова player.js (тот же критерий, что в
/// ExtractionOrchestrator/StreamResolver): cipher ИЛИ прямой url с n.
bool _needsJs(Map<String, dynamic> f) {
  if (f['signatureCipher'] != null || f['cipher'] != null) return true;
  final u = f['url'] as String?;
  if (u == null) return false;
  return Uri.parse(u).queryParameters.containsKey('n');
}

Future<String> _httpGetString(String url) async {
  final resp = await http
      .get(Uri.parse(url), headers: const {'User-Agent': _desktopUA})
      .timeout(const Duration(seconds: 30));
  if (resp.statusCode != 200) {
    throw KMEPException(KMEPErrorCode.nsigFail,
        'GET $url -> HTTP ${resp.statusCode}');
  }
  return resp.body;
}

/// Range-чек готового URL: bytes=0-1023, ждём 206 (или 200).
Future<String> _rangeStatus(String url) async {
  try {
    final resp = await http
        .get(Uri.parse(url),
            headers: const {'Range': 'bytes=0-1023', 'User-Agent': _desktopUA})
        .timeout(const Duration(seconds: 15));
    return '${resp.statusCode}';
  } catch (e) {
    return 'ERR(${e.runtimeType})';
  }
}

void main() => runApp(const HarnessApp());

class HarnessApp extends StatelessWidget {
  const HarnessApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'kmep-proto harness',
        theme: ThemeData.dark(useMaterial3: true),
        home: const TestScreen(),
      );
}

class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  final List<String> _log = [];
  final ScrollController _scroll = ScrollController();
  bool _running = false;
  String _verdict = '';

  void log(String line) {
    debugPrint(line);
    setState(() => _log.add(line));
    Timer(const Duration(milliseconds: 50), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _log.clear();
      _verdict = '';
    });

    var allOk = true;
    // Версия сборки харнеса — чтобы лог всегда однозначно идентифицировал,
    // какой именно APK его породил.
    log('harness v15 (полный StreamResolver e2e: WEB -> player.js -> '
        'WebView -> готовые URL всех форматов)');

    // Все созданные JS-рантаймы: в конце прогона освобождаем.
    final runtimes = <WebViewJsRuntime>[];

    // ---------- A. Baseline: ANDROID_VR без JS ----------
    try {
      log('== A. Baseline: ANDROID_VR (без player.js) ==');
      final sw = Stopwatch()..start();
      final resp = await http
          .post(
            Uri.parse('https://www.youtube.com/youtubei/v1/player'),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent':
                  'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
              'X-YouTube-Client-Name': '28',
              'X-YouTube-Client-Version': '1.65.10',
            },
            body: jsonEncode({
              'videoId': 'dQw4w9WgXcQ',
              'context': {
                'client': {
                  'clientName': 'ANDROID_VR',
                  'clientVersion': '1.65.10',
                  'deviceMake': 'Oculus',
                  'deviceModel': 'Quest 3',
                  'androidSdkVersion': 32,
                  'osName': 'Android',
                  'osVersion': '12L',
                  'hl': 'en',
                  'gl': 'US',
                }
              },
              'contentCheckOk': true,
              'racyCheckOk': true,
            }),
          )
          .timeout(const Duration(seconds: 20));
      sw.stop();
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final status =
          (json['playabilityStatus']?['status'] ?? '?').toString();
      final formats = <Map<String, dynamic>>[
        ...?((json['streamingData']?['formats'] as List?)?.cast<Map<String, dynamic>>()),
        ...?((json['streamingData']?['adaptiveFormats'] as List?)?.cast<Map<String, dynamic>>()),
      ];
      final direct = formats.where((f) => f['url'] != null).length;
      final maxH = formats.fold<int>(0, (m, f) {
        final h = (f['height'] as num?)?.toInt() ?? 0;
        return h > m ? h : m;
      });
      final ok = status == 'OK' && direct > 0;
      if (!ok) allOk = false;
      log('A[${sw.elapsedMilliseconds} ms] HTTP ${resp.statusCode}: '
          'status=$status форматов=${formats.length} прямых=$direct maxH=$maxH '
          '-> ${ok ? "PASS" : "FAIL"}');
      if (!ok) {
        log('reason: ${json['playabilityStatus']?['reason']}');
      }
    } catch (e, st) {
      allOk = false;
      log('A FAIL: $e\n$st');
    }

    // ---------- B. WebViewJsRuntime (системный движок) ----------
    try {
      log('== B. WebViewJsRuntime ==');
      var sw = Stopwatch()..start();
      final runtime = WebViewJsRuntime();
      runtimes.add(runtime);
      log('B движок создан за ${sw.elapsedMilliseconds} ms');

      sw.reset();
      final rawPlayerJs = await rootBundle.loadString('assets/player_dump.js');
      log('B player.js из ассета: ${rawPlayerJs.length} байт '
          '(${sw.elapsedMilliseconds} ms)');

      sw.reset();
      // В WebView browser_shim НЕ нужен: window/document/navigator настоящие,
      // origin = youtube.com через loadDataWithBaseURL.
      await runtime.bootstrapParts([
        preparePlayerJs(rawPlayerJs),
        discoverResolveFnScript,
      ]);
      log('B bootstrap (2 части): ${sw.elapsedMilliseconds} ms');

      // Снимок JS-контекста: эхо бридга, origin, целостность встроек,
      // сколько функций выгрузил коллектор, какая fn выбрана. По этому
      // блоку видно, ГДЕ именно рвётся цепочка player.js -> n-transform.
      final env = await runtime.envSnapshot();
      log('B env: echo=${env['echo']} href=${env['href']} '
          'origin=${env['origin']}');
      log('B env: strOk=${env['strOk']} jsonOk=${env['jsonOk']} '
          'doc=${env['doc']} winSame=${env['winSame']}');
      log('B env: fns=${env['fns']} fn=${env['fn']} '
          'fnName="${env['fnName']}"');

      // Эталон получен на ПК через Node на ЭТОЙ версии плеера.
      const inputN = '2w9J-B1FRC9th79L';
      const expectedN = 'hijUNSr2Sb4f-A';
      const inputUrl =
          'https://rr1---sn-x.googlevideo.com/videoplayback'
          '?expire=1799999999&id=TESTTESTTEST&n=$inputN&ratebypass=yes';

      sw.reset();
      // Маркер: та же форма (присваивание globalThis + IIFE + return
      // строки), но без вызова плеерного кода. Отличает «сломана
      // механика вызова» от «ломается внутри ji/KW».
      final marker = await runtime.call(
        'globalThis.__kmepMarker=(function(){return "MARKER42"})()',
      );
      log('B маркер: $marker');

      final outUrl = await runtime.call(
        'globalThis.__kmepOut=(function(){'
        'var f=globalThis.__kmepResolveFn;'
        'if(!f||typeof f!=="function"){'
        'throw new Error("resolve fn not discovered")}'
        'return String(f(${jsonEncode(inputUrl)},"","").KW())})()',
      );
      log('B call(ji+KW): ${sw.elapsedMilliseconds} ms');

      // Диагностика: какая функция выбрана и что в итоговом URL.
      final fnName = await runtime.call(
          'String(globalThis.__kmepResolveFnName || "?")');
      log('B выбранная функция: $fnName');
      final probe = await runtime.call(
        'globalThis.__kmepProbe=(function(){'
        'var f=globalThis.__kmepResolveFn;'
        'var o=f(${jsonEncode(inputUrl)},"","");'
        'return JSON.stringify({'
        'getN:String(o.get("n")),'
        'kwHasAlr:String(o.KW()).indexOf("alr=yes")!==-1,'
        'kwLen:String(o.KW()).length})})()',
      );
      log('B probe(get(n) до KW): $probe');

      final outN = Uri.parse(outUrl.trim()).queryParameters['n'] ?? '';
      final pass = outN == expectedN;
      if (!pass) allOk = false;
      log('B outUrl(${outUrl.length}): ${outUrl.substring(0, outUrl.length > 140 ? 140 : outUrl.length)}');
      log('B n: "$inputN" -> "$outN" (эталон "$expectedN") '
          '-> ${pass ? "PASS" : "FAIL"}');
    } catch (e, st) {
      allOk = false;
      log('B FAIL: $e\n$st');
    }

    // ---------- C. Полный StreamResolver e2e ----------
    // Реальный videoId -> watch-meta (STS + player.js URL) -> WEB InnerTube
    // -> СКАЧИВАНИЕ player.js по сети -> бутстрап в свежем WebView через
    // ПРОДАКШЕН-StreamResolver -> resolve ВСЕХ форматов -> Range-чек
    // каждого готового URL.
    try {
      log('== C. Полный StreamResolver e2e ==');
      const videoId = 'dQw4w9WgXcQ';
      var sw = Stopwatch()..start();

      // C1. Watch-page метаданные: STS для WEB + URL актуального player.js.
      final meta = await HttpWatchPageMetaProvider().fetch(videoId);
      final sts = meta?.signatureTimestamp;
      final jsUrl = meta?.playerJsUrl;
      if (jsUrl == null || jsUrl.isEmpty) {
        throw const KMEPException(
            KMEPErrorCode.nsigFail, 'C1: watch-страница не дала playerJsUrl');
      }
      log('C1[${sw.elapsedMilliseconds} ms] meta: STS=$sts '
          'player.js=${Uri.parse(jsUrl).path}');

      // C2. Реальный InnerTubeClient (WEB): сырые форматы с cipher/n.
      sw.reset();
      final web = InnerTubeClient(ClientRegistry.resolved('WEB'));
      final raw = await web.fetchPlayer(videoId, signatureTimestamp: sts);
      final webStatus =
          (raw['playabilityStatus']?['status'] ?? '?').toString();
      var formats = PlayerParser.rawFormats(raw);
      var srcName = 'WEB';
      if (webStatus != 'OK' || !formats.any(_hasSource)) {
        // Фолбэк источника форматов: ANDROID_VR (прямые url, часть с n).
        log('C2 WEB status=$webStatus url-источников='
            '${formats.where(_hasSource).length} -> фолбэк ANDROID_VR');
        sw.reset();
        final vr = InnerTubeClient(ClientRegistry.resolved('ANDROID_VR'));
        final vraw = await vr.fetchPlayer(videoId);
        final vstatus =
            (vraw['playabilityStatus']?['status'] ?? '?').toString();
        formats = PlayerParser.rawFormats(vraw);
        srcName = 'ANDROID_VR($vstatus)';
      }
      log('C2[${sw.elapsedMilliseconds} ms] источник=$srcName: '
          'форматов=${formats.length} с-url=${formats.where(_hasSource).length} '
          'требуют-playerJs=${formats.where(_needsJs).length}');
      if (!formats.any(_hasSource)) {
        throw const KMEPException(KMEPErrorCode.partial,
            'C2: ни одного формата с url/signatureCipher');
      }

      // C3. Продакшен-StreamResolver на свежем WebViewJsRuntime:
      // fetchPlayerJs качает player.js ПО СЕТИ, bootstrapParts гоняет
      // shim+player+discovery через WebView (тот же код, что в проде).
      sw.reset();
      final runtimeC = WebViewJsRuntime();
      runtimes.add(runtimeC);
      var playerJsSize = 0;
      final resolver = StreamResolver(
        jsRuntime: runtimeC,
        fetchPlayerJs: (url) async {
          final body = await _httpGetString(url);
          playerJsSize = body.length;
          return body;
        },
      );
      final streams = await resolver.resolve(formats, playerJsUrl: jsUrl);
      final env = await runtimeC.envSnapshot();
      log('C3[${sw.elapsedMilliseconds} ms] player.js=$playerJsSize байт; '
          'fns=${env['fns']} fn="${env['fnName']}"; '
          'resolve: вход ${formats.length} -> готово ${streams.length}');

      // C4. Range-чек КАЖДОГО готового URL: корректный n-transform даёт
      // 206/200 от CDN, битый — 403.
      sw.reset();
      var okCount = 0;
      for (final s in streams) {
        final st = await _rangeStatus(s.url);
        if (st.startsWith('2')) okCount++;
        log('  itag=${s.itag} ${s.type}'
            '${s.height != null ? " ${s.height}p" : ""} '
            '${s.mimeType.split(";").first}: HTTP $st');
      }
      final pass = streams.isNotEmpty && okCount * 5 >= streams.length * 4;
      if (!pass) allOk = false;
      log('C4[${sw.elapsedMilliseconds} ms] Range-чек всех URL: '
          '2xx=$okCount/${streams.length} -> ${pass ? "PASS" : "FAIL"}');
    } catch (e, st) {
      allOk = false;
      log('C FAIL: $e\n$st');
    }

    for (final r in runtimes) {
      try {
        r.dispose();
      } catch (_) {}
    }

    setState(() {
      _running = false;
      _verdict = allOk ? 'ИТОГ: PASS' : 'ИТОГ: FAIL';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('kmep-proto harness')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _running ? null : _run,
                  icon: _running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: Text(_running ? 'Выполняю...' : 'Run on-device test'),
                ),
              ),
            ),
            if (_verdict.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(_verdict,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _verdict.endsWith('PASS')
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    )),
              ),
            Expanded(
              child: Container(
                color: Colors.black,
                width: double.infinity,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(10),
                  child: SelectableText(
                    _log.join('\n'),
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12, height: 1.35),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
