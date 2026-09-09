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

import 'dart:convert';
import 'dart:io';

/// Дисковый кэш player.js: один релиз плеера ~2.5 МБ, качать его на каждый
/// запуск приложения расточительно. Ключ — URL, имя файла — устойчивый хеш.
class DiskPlayerJsCache {
  final Directory dir;
  final Future<String> Function(String url) fetch;

  DiskPlayerJsCache({Directory? cacheDir, required this.fetch})
      : dir = cacheDir ??
            Directory(
                '${Platform.environment['HOME'] ?? Directory.systemTemp.path}/.cache/kmep');

  String _fileName(String url) =>
      base64Url.encode(utf8.encode(url)).replaceAll('=', '');

  Future<String> get(String url) async {
    await dir.create(recursive: true);
    final file = File('${dir.path}/player_${_fileName(url)}.js');
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) return content;
    }
    final content = await fetch(url);
    await file.writeAsString(content, flush: true);
    return content;
  }
}

/// HTTP-фетчер RemoteConfig: отдаёт тело ответа строкой или null при любой
/// ошибке (RemoteConfigLoader сам упадёт на дефолтную конфигурацию).
class HttpRemoteConfigFetcher {
  final Uri url;
  final Duration timeout;
  final Map<String, String> headers;

  HttpRemoteConfigFetcher(this.url,
      {this.timeout = const Duration(seconds: 5), this.headers = const {}});

  Future<String?> fetch() async {
    try {
      final client = HttpClient();
      try {
        final req = await client.getUrl(url).timeout(timeout);
        for (final e in headers.entries) {
          req.headers.set(e.key, e.value);
        }
        final resp = await req.close().timeout(timeout);
        if (resp.statusCode != 200) return null;
        return await resp.transform(utf8.decoder).join().timeout(timeout);
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }
}
