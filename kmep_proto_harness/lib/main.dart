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
import 'flutter_js_runtime.dart';

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
    log('harness v9 (stackSize matrix)');

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

    // ---------- B. Матрица stackSize: лечит ли jsSetMaxStackSize ----------
    try {
      log('== B. Матрица stackSize (свежий движок на каждый) ==');
      final rawPlayerJs = await rootBundle.loadString('assets/player_dump.js');
      final parts = [
        browserShimScript,
        preparePlayerJs(rawPlayerJs),
        discoverResolveFnScript,
      ];

      const sizes = <int?>[
        null, // дефолт пакета (1 МБ)
        8 * 1024 * 1024,
        32 * 1024 * 1024,
        256 * 1024 * 1024,
      ];
      var anyOk = false;
      for (final size in sizes) {
        final sw = Stopwatch()..start();
        final label = size == null ? 'default(1MB)' : '${size >> 20}MB';
        String? err;
        try {
          final runtime = FlutterJsRuntime(stackSize: size);
          await runtime.bootstrapParts(parts);
          log('B [$label]: OK за ${sw.elapsedMilliseconds} ms');
          anyOk = true;
        } catch (e) {
          err = '$e';
          log('B [$label]: FAIL — ${err.split('\n').first}');
        }
      }
      if (!anyOk) {
        allOk = false;
        log('B ВЫВОД: jsSetMaxStackSize НЕ влияет — рассогласование '
            'подсчёта стека в компиляторе/ридере, не переполнение.');
      }

      // Если хоть один размер прошёл — гоняем эталон ji на нём.
      if (anyOk) {
        const inputN = '2w9J-B1FRC9th79L';
        const expectedN = 'hijUNSr2Sb4f-A';
        const inputUrl =
            'https://rr1---sn-x.googlevideo.com/videoplayback'
            '?expire=1799999999&id=TESTTESTTEST&n=$inputN&ratebypass=yes';
        for (final size in sizes) {
          final sw = Stopwatch()..start();
          try {
            final runtime = FlutterJsRuntime(stackSize: size);
            await runtime.bootstrapParts(parts);
            final outUrl = await runtime.call(
              'globalThis.__kmepOut=(function(){'
              'var f=globalThis.__kmepResolveFn;'
              'if(!f||typeof f!=="function"){'
              'throw new Error("resolve fn not discovered")}'
              'return String(f(${jsonEncode(inputUrl)},"","").KW())})()',
            );
            final outN = Uri.parse(outUrl.trim()).queryParameters['n'] ?? '';
            final pass = outN == expectedN;
            log('B ji[${size == null ? "default" : "${size >> 20}MB"}] '
                '(${sw.elapsedMilliseconds} ms): n="$outN" -> '
                '${pass ? "PASS" : "FAIL"}');
            break; // первый прошедший бустрап движок достаточен
          } catch (e) {
            log('B ji[${size ?? "default"}]: bootstrap FAIL, пробую следующий размер');
          }
        }
      }
    } catch (e, st) {
      allOk = false;
      log('B FAIL: $e\n$st');
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
