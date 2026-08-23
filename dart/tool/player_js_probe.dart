// Диагностический инструмент — НЕ часть runtime-кода приложения.
//   cd dart && dart pub get && dart run tool/player_js_probe.dart <videoId>
//
// v3: v1/v2 гадали по форме кода (какие методы вызываются, как выглядит
// объект-операций) — и оба промазали, потому что форма меняется от сборки
// к сборке. v3 ищет по точке входа get("n")/get('n') в коде — устойчивее
// формы, хотя тоже может промахнуться (см. docs/AGENT_HANDOFF.md — этот
// анкер тоже оказался не тем местом, реальный путь лежит через полное
// выполнение player.js, см. tool/find_nsig.js).

import 'dart:convert';
import 'dart:io';

const _watchUrlTemplate = 'https://www.youtube.com/watch?v=%s&hl=en&gl=US';

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/player_js_probe.dart <videoId>');
    exit(1);
  }
  final videoId = args.first;

  stdout.writeln('== 1. Скачиваю watch-страницу для $videoId ==');
  final client = HttpClient();
  final watchHtml = await _fetch(client, _watchUrlTemplate.replaceAll('%s', videoId));

  stdout.writeln('== 2. Ищу URL player.js в HTML ==');
  final playerJsUrl = _extractPlayerJsUrl(watchHtml);
  if (playerJsUrl == null) {
    stderr.writeln('Не нашёл ссылку на player.js в watch-странице.');
    exit(2);
  }
  stdout.writeln('Найден: $playerJsUrl');

  stdout.writeln('== 3. Скачиваю player.js ==');
  final playerJs = await _fetch(client, playerJsUrl);
  stdout.writeln('Размер: ${playerJs.length} байт');

  final dumpFile = File('player_js_dump.js');
  await dumpFile.writeAsString(playerJs);
  stdout.writeln('Полный player.js сохранён в ${dumpFile.path}.');

  stdout.writeln('\n== 4. Ищу точку входа get("n") / get(\'n\') ==');
  final anchorPattern = RegExp('''\\.get\\(\\s*["']n["']\\s*\\)''');
  final anchors = anchorPattern.allMatches(playerJs).toList();

  if (anchors.isEmpty) {
    stdout.writeln('Не нашёл ни одного get("n") / get(\'n\'). Смотри '
        '${dumpFile.path} руками, или сразу переходи к tool/find_nsig.js '
        '(более надёжный подход — полное выполнение файла).');
    client.close();
    return;
  }

  stdout.writeln('Найдено анкеров: ${anchors.length}. Разбираю контекст каждого:\n');

  for (var i = 0; i < anchors.length; i++) {
    final m = anchors[i];
    final ctxStart = (m.start - 120).clamp(0, playerJs.length);
    final ctxEnd = (m.end + 250).clamp(0, playerJs.length);
    final context = playerJs.substring(ctxStart, ctxEnd);
    stdout.writeln('--- Анкер #$i (позиция ${m.start}) ---');
    stdout.writeln(context);
    stdout.writeln('');
  }

  stdout.writeln('ПРИМЕЧАНИЕ: этот анкер исторически указывал на служебную '
      'функцию синхронизации URL (не саму nsig-трансформацию). Основной '
      'рабочий путь сейчас — tool/find_nsig.js (bootstrap+перебор '
      '_yt_player). Используй этот вывод как доп. контекст, не как ответ.');

  client.close();
}

Future<String> _fetch(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set('User-Agent',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36');
  final response = await request.close();
  return await response.transform(utf8.decoder).join();
}

String? _extractPlayerJsUrl(String watchHtml) {
  final match = RegExp(r'"jsUrl":"([^"]+base\.js)"').firstMatch(watchHtml) ??
      RegExp(r'src="(/s/player/[^"]+base\.js)"').firstMatch(watchHtml);
  if (match == null) return null;
  final path = match.group(1)!.replaceAll(r'\/', '/');
  return path.startsWith('http') ? path : 'https://www.youtube.com$path';
}
