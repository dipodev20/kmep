// Отладка потери форматов в resolve(): прогоняет цикл резолвера вручную
// по свежему WEB playerResponse и печатает судьбу каждого формата.
//
//   dart run tool/debug_web_resolve.dart [videoId]

import 'dart:convert';
import 'dart:io';

import 'package:kmep/kmep.dart';

Future<String> httpGet(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36');
    final resp = await req.close();
    return await resp.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

Future<void> main(List<String> args) async {
  final videoId = args.isEmpty ? 'dQw4w9WgXcQ' : args.first;
  final html = await httpGet('https://www.youtube.com/watch?v=$videoId&hl=en&gl=US');
  final apiKey = RegExp(r'"INNERTUBE_API_KEY":"([^"]+)"').firstMatch(html)!.group(1)!;
  final sts = int.parse(RegExp(r'"STS":(\d+)').firstMatch(html)!.group(1)!);
  final jsUrl = RegExp(r'"jsUrl":"([^"]+base\.js)"').firstMatch(html)?.group(1)?.replaceAll(r'\/', '/');

  final hc = HttpClient();
  final req = await hc.postUrl(Uri.parse(
      'https://www.youtube.com/youtubei/v1/player?key=$apiKey'));
  req.headers.set('Content-Type', 'application/json');
  req.add(utf8.encode(jsonEncode({
    'videoId': videoId,
    'context': {
      'client': {'clientName': 'WEB', 'clientVersion': '2.20240808.00.00', 'hl': 'en', 'gl': 'US'},
    },
    'playbackContext': {'contentPlaybackContext': {'signatureTimestamp': sts}},
    'racyCheckOk': true,
    'contentCheckOk': true,
  })));
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  hc.close();
  final raw = jsonDecode(body) as Map<String, dynamic>;

  final formats = PlayerParser.rawFormats(raw);
  stdout.writeln('форматов: ${formats.length}');

  final jsRuntime = NodeProcessJsRuntime(callTimeout: const Duration(seconds: 60));
  final resolver = StreamResolver(
    jsRuntime: jsRuntime,
    fetchPlayerJs: (_) async => await httpGet(
        jsUrl != null && jsUrl.startsWith('http') ? jsUrl : 'https://www.youtube.com$jsUrl'),
  );

  var okCount = 0;
  for (var i = 0; i < formats.length; i++) {
    final f = formats[i];
    final cipher = f['signatureCipher'] ?? f['cipher'];
    if (f['url'] == null && cipher == null) {
      stdout.writeln('#$i itag=${f['itag']}: нет ни url, ни cipher — SKIP');
      continue;
    }
    try {
      String? url = f['url'] as String?;
      if (url == null) {
        final params = Uri.splitQueryString(cipher as String);
        url = params['url'];
      }
      if (url == null) {
        stdout.writeln('#$i itag=${f['itag']}: cipher без url — SKIP');
        continue;
      }
      final resolved = await resolver.resolve([f], playerJsUrl: 'debug');
      if (resolved.isEmpty) {
        stdout.writeln('#$i itag=${f['itag']}: resolve вернул пусто');
      } else {
        okCount++;
        if (okCount <= 3) {
          stdout.writeln('#$i itag=${f['itag']} OK: ${resolved.first.url.substring(0, 80)}...');
        }
      }
    } catch (e) {
      stdout.writeln('#$i itag=${f['itag']}: ОШИБКА $e');
    }
  }
  stdout.writeln('\nуспешно: $okCount/${formats.length}');
  jsRuntime.dispose();
}
