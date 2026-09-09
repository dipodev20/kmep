// KMEP — a from-scratch YouTube extraction library for Dart.
// Copyright (C) 2026 dipodev20
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// Простой live-бенчмарк KMEP: холодный запуск (bootstrap node-рантайма +
// player.js + POT) и тёплый кэш-хит. Живой сетевой проход, не мок.
//
// Запуск: dart run tool/bench_kmep.dart [videoId ...]
//
// Для сравнения с yt-dlp на том же устройстве/IP/клиенте:
//   python3 -m yt_dlp -J --no-warnings -q \
//     --extractor-args 'youtube:player_client=android_vr' \
//     --extractor-args 'youtube:player_skip=webpage,configs' \
//     'https://youtube.com/watch?v=dQw4w9WgXcQ'
// (если в окружении стоит bgutil-POT плагин: YTDLP_NO_PLUGINS=1)
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:kmep/kmep.dart';

Future<String> fetchText(String url) async {
  final resp = await http.get(Uri.parse(url), headers: const {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
  });
  return resp.body;
}

Future<void> main(List<String> args) async {
  final videos = args.isNotEmpty ? args : ['dQw4w9WgXcQ'];
  final kmep = Kmep.withOnDevicePoToken(
    jsRuntime: NodeProcessJsRuntime(),
    potJsRuntime: NodeProcessJsRuntime(),
    fetchText: fetchText,
  );

  for (final vid in videos) {
    final cold = Stopwatch()..start();
    try {
      final v = await kmep.getVideo(vid);
      final coldSecs = cold.elapsedMilliseconds / 1000;
      stdout.writeln(
          '$vid: cold ${coldSecs.toStringAsFixed(2)}s ok, ${v.streams.length} streams'
          ' (includes node + player.js + POT bootstrap)');

      final warm = Stopwatch()..start();
      await kmep.getVideo(vid);
      stdout.writeln(
          '$vid: cached ${warm.elapsedMilliseconds}ms (metadata + resolved URLs)');
    } on KMEPException catch (e) {
      stdout.writeln('$vid: FAIL ${e.code} — ${e.message}');
      final diag = kmep.lastPoTokenError;
      if (diag != null) stdout.writeln('  PO token diagnostic: $diag');
    }
  }
  exit(0);
}
