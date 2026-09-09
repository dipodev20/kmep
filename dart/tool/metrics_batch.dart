// МЕТРИКИ SUCCESS RATE для решения о переносе в KMP.
//
// Собирает выборку видео через InnerTube-поиск по нескольким категориям,
// прогоняет каждую через ПОЛНЫЙ ExtractionOrchestrator (как будет в проде),
// классифицирует исходы и пишет JSON-отчёт.
//
//   dart run tool/metrics_batch.dart [кол-во] [файл-с-videoId]
//
// Без аргументов: ~54 видео из поиска + санити-якорь. Отчёт:
// /tmp/opencode/kmep_metrics.json + сводка в stdout.

import 'dart:convert';
import 'dart:io';

import 'package:kmep/kmep.dart';

const _desktopUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';
const _sanityVideo = 'dQw4w9WgXcQ';

const _searchQueries = [
  'music',
  'gaming',
  'news today',
  'cooking recipe',
  'travel vlog',
  'python programming',
  'space documentary',
  'football highlights',
  'podcast interview',
  'diy home repair',
];

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

/// Рекурсивно собирает все значения videoId из JSON ответа поиска.
void collectVideoIds(dynamic node, List<String> out) {
  if (node is Map<String, dynamic>) {
    final vid = node['videoId'];
    if (vid is String && RegExp(r'^[\w-]{11}$').hasMatch(vid)) out.add(vid);
    for (final v in node.values) {
      collectVideoIds(v, out);
    }
  } else if (node is List) {
    for (final v in node) {
      collectVideoIds(v, out);
    }
  }
}

Future<List<String>> buildSample(int targetSize) async {
  // Поиск через конфиг WEB (проверенный ключ); поисковой эндпоинт не требует
  // STS и устойчивее player-эндпоинта.
  const searchClient = ClientRegistry.web;
  final innerTube = InnerTubeClient(searchClient);
  final ids = <String>{};
  try {
    for (final q in _searchQueries) {
      if (ids.length >= targetSize - 1) break;
      try {
        final resp = await innerTube.fetchSearch(q);
        final found = <String>[];
        collectVideoIds(resp, found);
        // videoId повторяется во вложенных рендерерах одного результата,
        // поэтому дедуп до взятия первых N.
        final uniqueInResponse = found.toSet();
        ids.addAll(uniqueInResponse.take(targetSize ~/ _searchQueries.length + 2));
        stdout.writeln('поиск "$q": ${found.length} упоминаний, '
            '${uniqueInResponse.length} уникальных');
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        stdout.writeln('поиск "$q": ошибка ($e)');
      }
    }
  } finally {
    innerTube.close();
  }
  ids.add(_sanityVideo); // якорь: заведомо рабочий случай
  return ids.take(targetSize).toList();
}

enum Outcome { ok, botCheck, noStreams, apiRejected, rateLimited, urlRejected, other }

Outcome classify(String combined) {
  if (combined.contains('Sign in to confirm')) return Outcome.botCheck;
  if (combined.contains('No streams from') || combined.contains('SABR')) {
    return Outcome.noStreams;
  }
  if (combined.contains('HTTP 400') || combined.contains('FAILED_PRECONDITION')) {
    return Outcome.apiRejected;
  }
  if (combined.contains('rateLimited') || combined.contains('429')) return Outcome.rateLimited;
  return Outcome.other;
}

Future<void> main(List<String> args) async {
  var targetSize = 50;
  List<String>? fromFile;
  String? potScriptPath;
  Uri? potHttpUrl;
  final rest = <String>[];
  for (final a in args) {
    if (a.startsWith('--pot-script=')) {
      potScriptPath = a.substring('--pot-script='.length);
    } else if (a.startsWith('--pot-http=')) {
      potHttpUrl = Uri.parse(a.substring('--pot-http='.length));
    } else if (a == '--pot-http') {
      potHttpUrl = Uri.parse('http://127.0.0.1:4416');
    } else {
      rest.add(a);
    }
  }
  if (rest.isNotEmpty) targetSize = int.tryParse(rest[0]) ?? 50;
  if (rest.length > 1) {
    fromFile =
        File(rest[1]).readAsLinesSync().map((l) => l.trim()).where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
  }

  final sample = fromFile ?? await buildSample(targetSize);
  final potMode = potHttpUrl != null
      ? 'HTTP-сервер $potHttpUrl'
      : potScriptPath != null
          ? 'скрипт $potScriptPath'
          : 'выкл';
  stdout.writeln('\nВыборка: ${sample.length} видео (PO token: $potMode)\n');

  final jsRuntime = NodeProcessJsRuntime();
  final playerJsCache = <String, String>{};
  final orchestrator = ExtractionOrchestrator(
    config: const RemoteConfig(),
    cache: InMemoryCacheManager(), // каждый videoId уникален, кэш почти не работает
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
    poTokenProvider: potHttpUrl != null
        ? BgutilHttpPoTokenProvider(baseUrl: potHttpUrl)
        : potScriptPath != null
            ? BgutilScriptPoTokenProvider(scriptPath: potScriptPath)
            : null,
  );

  final reports = <Map<String, dynamic>>[];
  var done = 0;

  Future<void> processOne(String videoId) async {
    final entry = <String, dynamic>{'videoId': videoId};
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
            final resp = await req.close().timeout(const Duration(seconds: 10));
            await resp.drain<void>();
            httpStatus = resp.statusCode.toString();
          } finally {
            client.close();
          }
        } catch (_) {}
      }
      final ok = best != null && httpStatus.startsWith('2');
      entry['title'] = video.title;
      entry['streams'] = video.streams.length;
      entry['maxH'] = best?.height ?? 0;
      entry['http'] = httpStatus;
      entry['outcome'] = ok ? 'ok' : 'urlRejected';
    } on KMEPException catch (e) {
      entry['outcome'] = classify('${e.code.name} ${e.message}').name;
      entry['error'] = e.message.length > 300 ? '${e.message.substring(0, 300)}...' : e.message;
    } catch (e) {
      entry['outcome'] = 'other';
      entry['error'] = '$e';
    }
    reports.add(entry);
    done++;
    stdout.writeln('[${done.toString().padLeft(3)}/${sample.length}] '
        '$videoId -> ${entry['outcome']}'
        '${entry['outcome'] == 'ok' ? ' maxH=${entry['maxH']}' : ''}');
  }

  // Конкурентность 3 с лёгким разбросом старта — бережём лимиты.
  final queue = List<String>.from(sample);
  final workers = List.generate(3, (_) async {
    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      await processOne(id);
      await Future.delayed(const Duration(milliseconds: 150));
    }
  });
  await Future.wait(workers);

  // Сводка.
  final counts = <String, int>{};
  for (final r in reports) {
    counts[r['outcome'] as String] = (counts[r['outcome'] as String] ?? 0) + 1;
  }
  final okCount = counts['ok'] ?? 0;
  stdout.writeln('\n======== SUCCESS RATE ========');
  for (final e in counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
    stdout.writeln('${e.key.padRight(12)} ${e.value.toString().padLeft(3)}  '
        '${(e.value / reports.length * 100).toStringAsFixed(1)}%');
  }
  stdout.writeln('\nИТОГ ok: $okCount/${reports.length} = '
      '${(okCount / reports.length * 100).toStringAsFixed(1)}%');

  final reportFile = '/tmp/opencode/kmep_metrics.json';
  File(reportFile).writeAsStringSync(
      JsonEncoder.withIndent('  ').convert({'generatedAt': DateTime.now().toIso8601String(), 'total': reports.length, 'results': reports}));
  stdout.writeln('Отчёт: $reportFile');

  orchestrator.dispose();
  jsRuntime.dispose();
}
