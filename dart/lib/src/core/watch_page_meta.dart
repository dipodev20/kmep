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

/// Метаданные watch-страницы, нужные для cipher-резолва и сессионных
/// полей: signatureTimestamp (STS) для browser-клиентов, URL player.js
/// для StreamResolver, visitorData (ytcfg VISITOR_DATA) для клиентов,
/// которым она требуется (TV; та же строка потом привязывает PO token).
class WatchPageMeta {
  final int? signatureTimestamp;
  final String? playerJsUrl;
  final String? visitorData;
  const WatchPageMeta(
      {this.signatureTimestamp, this.playerJsUrl, this.visitorData});
}

/// Абстракция над получением WatchPageMeta — оркестратор зависит только
/// от неё, чтобы оставаться тестируемым без сети.
abstract class WatchPageMetaProvider {
  Future<WatchPageMeta?> fetch(String videoId);
}

/// Реальная реализация через GET watch-страницы.
///
/// Регэкспы те же, что в tool/e2e_live_test.dart — держим синхронно.
/// Любая ошибка сети/парса -> null (оркестратор продолжит без meta,
/// cipher-форматы в этом случае не резолвятся и клиент считается неудачей).
class HttpWatchPageMetaProvider implements WatchPageMetaProvider {
  final String watchUrlTemplate;
  final Duration timeout;

  HttpWatchPageMetaProvider({
    this.watchUrlTemplate = 'https://www.youtube.com/watch?v=%s&hl=en&gl=US',
    this.timeout = const Duration(seconds: 8),
  });

  @override
  Future<WatchPageMeta?> fetch(String videoId) async {
    try {
      final client = HttpClient();
      try {
        final req = await client
            .getUrl(Uri.parse(watchUrlTemplate.replaceAll('%s', videoId)))
            .timeout(timeout);
        req.headers.set('User-Agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36');
        final resp = await req.close().timeout(timeout);
        final html = await resp.transform(utf8.decoder).join().timeout(timeout);

        final stsStr = RegExp(r'"STS":(\d+)').firstMatch(html)?.group(1);
        String? jsUrl;
        final m = RegExp(r'"jsUrl":"([^"]+base\.js)"').firstMatch(html) ??
            RegExp(r'src="(/s/player/[^"]+base\.js)"').firstMatch(html);
        if (m != null) {
          final p = m.group(1)!.replaceAll(r'\/', '/');
          jsUrl = p.startsWith('http') ? p : 'https://www.youtube.com$p';
        }
        // ytcfg VISITOR_DATA — JSON-строка с экранированием, раскодируем.
        String? visitorData;
        final vdRaw = RegExp(r'"VISITOR_DATA":"((?:[^"\\]|\\.)*)"')
            .firstMatch(html)
            ?.group(1);
        if (vdRaw != null) {
          try {
            visitorData = jsonDecode('"$vdRaw"') as String;
          } catch (_) {}
        }
        return WatchPageMeta(
          signatureTimestamp: stsStr == null ? null : int.parse(stsStr),
          playerJsUrl: jsUrl,
          visitorData: visitorData,
        );
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }
}

/// Caches watch-page metadata per video for [ttl] (default 10 minutes).
/// [ExtractionOrchestrator] already caches within a single video fetch,
/// but PO token providers commonly need the same metadata again (e.g.
/// for `visitorData` binding) — wrap your real provider in this so the
/// watch page is only fetched once per video across both call sites.
class CachedWatchPageMetaProvider implements WatchPageMetaProvider {
  final WatchPageMetaProvider _inner;
  final Duration ttl;
  final _cache = <String, _CachedMeta>{};

  CachedWatchPageMetaProvider(this._inner,
      {this.ttl = const Duration(minutes: 10)});

  @override
  Future<WatchPageMeta?> fetch(String videoId) async {
    final cached = _cache[videoId];
    if (cached != null && !cached.isExpired) return cached.value;
    final meta = await _inner.fetch(videoId);
    _cache[videoId] = _CachedMeta(meta, DateTime.now().add(ttl));
    return meta;
  }

  /// Drops all cached entries (e.g. on a "hard refresh" action).
  void clear() => _cache.clear();
}

class _CachedMeta {
  final WatchPageMeta? value;
  final DateTime expiresAt;
  _CachedMeta(this.value, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
