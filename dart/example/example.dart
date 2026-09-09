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

// Runnable example for a plain Dart/server target (uses NodeProcessJsRuntime,
// so it needs `node` on PATH). For Flutter, swap NodeProcessJsRuntime for
// WebViewJsRuntime from ../flutter_integration and use two separate
// instances (one for player.js, one for BotGuard) — see README "Platform
// integration".
//
// Run with: dart run example/example.dart <videoId>
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:kmep_proto/kmep.dart';

Future<String> fetchText(String url) async {
  final resp = await http.get(Uri.parse(url), headers: const {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
  });
  if (resp.statusCode != 200) {
    throw StateError('GET $url -> HTTP ${resp.statusCode}');
  }
  return resp.body;
}

Future<void> main(List<String> args) async {
  final videoId = args.isNotEmpty ? args.first : 'dQw4w9WgXcQ';

  // Two separate JS contexts: running BotGuard and player.js in the same
  // globals has caused cross-contamination in testing.
  final kmep = Kmep.withOnDevicePoToken(
    jsRuntime: NodeProcessJsRuntime(),
    potJsRuntime: NodeProcessJsRuntime(),
    fetchText: fetchText,
  );

  print('Fetching video info for $videoId ...');
  try {
    final video = await kmep.getVideo(videoId);
    print('Title:    ${video.title}');
    print('Channel:  ${video.channelName}');
    print('Duration: ${video.durationSeconds}s');
    print('Streams:  ${video.streams.length}');
    for (final s in video.streams.take(3)) {
      print('  - ${s.type} ${s.quality} ${s.mimeType}');
    }
  } on KMEPException catch (e) {
    stderr.writeln('Extraction failed: ${e.code} — ${e.message}');
    final lastPotError = kmep.lastPoTokenError;
    if (lastPotError != null) {
      stderr.writeln('PO token diagnostic: $lastPotError');
    }
    exitCode = 1;
    return;
  }

  print('\nSearching "lofi hip hop" ...');
  final results = await kmep.search('lofi hip hop');
  for (final r in results.results.take(5)) {
    print(
        '  ${r.videoId}  ${r.title}  (${r.durationSeconds}s, ${r.viewCount} views)');
  }
}
