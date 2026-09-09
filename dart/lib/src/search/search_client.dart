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

import '../clients/client_configs.dart';
import '../clients/innertube_client.dart';
import '../models/kmep_models.dart';

/// A page of the shorts feed: items plus an opaque continuation token
/// (`null` means there are no more pages).
class ShortsFeedPage {
  final List<VideoSearchResult> items;
  final String? continuation;
  const ShortsFeedPage({required this.items, this.continuation});
}

/// InnerTube search filter (protobuf, base64) that returns only Shorts —
/// the same one YouTube's own "Shorts" search chip sends.
const String kShortsSearchParams = '8gEBGgIgAQ==';

/// Search and shorts-feed extraction. Does not need a [JsRuntime] or a
/// PO token provider — YouTube's `/search` endpoint is far more tolerant
/// than `/player` and works reliably on the WEB client alone.
///
/// Usually you get one of these from [Kmep.search], but it can be used
/// standalone if you only need search (e.g. a lightweight autocomplete
/// feature) without paying for the rest of the extraction stack.
class SearchClient {
  final InnerTubeClient _client;

  SearchClient({String hl = 'en', String gl = 'US'})
      : _hl = hl,
        _gl = gl,
        _client = InnerTubeClient(ClientRegistry.resolved('WEB'));

  final String _hl;
  final String _gl;

  /// Regular YouTube search. [continuation] paginates a previous result.
  Future<SearchResultPage> search(String query, {String? continuation}) async {
    final resp = await _client.fetchSearch(
      query,
      continuation: continuation,
      hl: _hl,
      gl: _gl,
    );
    return SearchResultPage(results: parseSearchResults(resp));
  }

  /// One page of a Shorts-only feed for [query]. Pass the previous
  /// page's [continuation] to fetch the next page.
  Future<ShortsFeedPage> shortsFeed({
    required String query,
    String? continuation,
  }) async {
    final resp = await _client.fetchSearch(
      query,
      continuation: continuation,
      params: continuation == null ? kShortsSearchParams : null,
      hl: _hl,
      gl: _gl,
    );
    final items = <VideoSearchResult>[];
    final seenIds = <String>{};
    String? nextToken;

    void walk(dynamic node) {
      if (node is Map) {
        final lockup = node['shortsLockupViewModel'];
        if (lockup is Map) {
          final item = _lockupToItem(lockup.cast<String, dynamic>());
          if (item != null && seenIds.add(item.videoId)) items.add(item);
        }
        if (node['continuationItemRenderer'] is Map) {
          final ce =
              (node['continuationItemRenderer'] as Map)['continuationEndpoint'];
          if (ce is Map && ce['continuationCommand'] is Map) {
            final t = ce['continuationCommand']['token'];
            if (t is String && t.isNotEmpty) nextToken = t;
          }
        }
        node.values.forEach(walk);
      } else if (node is List) {
        for (final v in node) {
          walk(v);
        }
      }
    }

    walk(resp);
    if (items.isEmpty && continuation == null) {
      throw const KMEPException(
          KMEPErrorCode.parseError, 'shorts feed is empty');
    }
    return ShortsFeedPage(items: items, continuation: nextToken);
  }

  void close() => _client.close();
}

/// `shortsLockupViewModel` -> [VideoSearchResult]. There's no channel name
/// on this renderer (it's not sent for shorts-shelf lockups).
VideoSearchResult? _lockupToItem(Map<String, dynamic> lockup) {
  String? videoId;
  try {
    final cmd = lockup['onTap']?['innertubeCommand'] as Map?;
    final reel = cmd?['reelWatchEndpoint'] as Map?;
    videoId = reel?['videoId']?.toString();
  } catch (_) {}
  if (videoId == null || videoId.isEmpty) return null;

  var title = '';
  var views = '';
  try {
    final om = lockup['overlayMetadata'] as Map?;
    title = om?['primaryText']?['content']?.toString() ?? '';
    views = om?['secondaryText']?['content']?.toString() ?? '';
  } catch (_) {}

  var thumb = '';
  try {
    final sources = (lockup['thumbnailViewModel'] as Map)['thumbnailViewModel']
        ['image']['sources'] as List;
    if (sources.isNotEmpty && sources.last is Map) {
      thumb = (sources.last as Map)['url']?.toString() ?? '';
    }
  } catch (_) {}

  return VideoSearchResult(
    videoId: videoId,
    title: title,
    channelName: '',
    durationSeconds: 0,
    viewCount: views.isNotEmpty ? viewsFromText(views) : 0,
    thumbnailUrl: thumb.startsWith('//') ? 'https:$thumb' : thumb,
    uploadDate: '',
    isShort: true,
  );
}

/// Recursively walks an InnerTube `/search` response and collects
/// `videoRenderer` / `gridVideoRenderer` / `reelItemRenderer` nodes,
/// deduplicated by video ID. Capped at 40 results per page (matches
/// what YouTube's own search page renders per batch).
List<VideoSearchResult> parseSearchResults(Map<String, dynamic> response) {
  final items = <VideoSearchResult>[];
  final seenIds = <String>{};

  void walk(dynamic node) {
    if (node is Map<String, dynamic>) {
      for (final key in const [
        'videoRenderer',
        'gridVideoRenderer',
        'reelItemRenderer',
      ]) {
        final r = node[key];
        if (r is Map) {
          final item = _rendererToItem(r.cast<String, dynamic>());
          if (item != null && seenIds.add(item.videoId)) items.add(item);
        }
      }
      for (final v in node.values) {
        walk(v);
      }
    } else if (node is List) {
      for (final v in node) {
        walk(v);
      }
    }
  }

  walk(response);
  return items.take(40).toList();
}

VideoSearchResult? _rendererToItem(Map<String, dynamic> r) {
  final id = r['videoId']?.toString();
  if (id == null || id.isEmpty) return null;

  final title = runsText(r['title']) ?? runsText(r['headline']) ?? '';
  final channelName = runsText(r['ownerText']) ??
      runsText(r['longBylineText']) ??
      runsText(r['shortBylineText']) ??
      '';
  final lengthText = runsText(r['lengthText']);
  final durationSeconds = lengthText != null ? lengthToSeconds(lengthText) : 0;
  final viewCountText = runsText(r['viewCountText']);
  final viewCount = viewCountText != null ? viewsFromText(viewCountText) : 0;

  return VideoSearchResult(
    videoId: id,
    title: title,
    channelName: channelName,
    durationSeconds: durationSeconds,
    viewCount: viewCount,
    thumbnailUrl: thumbnailUrlOf(r),
    uploadDate: runsText(r['publishedTimeText']) ?? '',
  );
}

/// Reads InnerTube's `{simpleText}` / `{runs:[{text}]}` text shape.
/// Exposed because it's generically useful when writing your own
/// parsers against renderers this library doesn't cover yet (channels,
/// comments, playlists).
String? runsText(dynamic obj) {
  if (obj is! Map) return null;
  final simple = obj['simpleText'];
  if (simple is String) return simple;
  final runs = obj['runs'];
  if (runs is List && runs.isNotEmpty && runs.first is Map) {
    final text = (runs.first as Map)['text'];
    if (text != null) return text.toString();
  }
  return null;
}

/// Parses a duration string like `"12:34"` or `"1:02:03"` into seconds.
int lengthToSeconds(String text) {
  final parts = text.split(':');
  if (parts.length > 3) return 0;
  var seconds = 0;
  for (final p in parts) {
    seconds = seconds * 60 + (int.tryParse(p.trim()) ?? 0);
  }
  return seconds;
}

/// Parses a localized view-count string (e.g. `"1.2M views"`) by
/// stripping everything but digits. Good enough for sorting/display;
/// not locale-aware beyond that.
int viewsFromText(String text) {
  final digits = text.replaceAll(RegExp('[^0-9]'), '');
  if (digits.isEmpty) return 0;
  return int.tryParse(digits) ?? 0;
}

/// Picks the highest-resolution thumbnail URL out of an InnerTube
/// `thumbnail.thumbnails[]` array, normalizing protocol-relative URLs.
String thumbnailUrlOf(Map<String, dynamic> renderer) {
  final thumb = renderer['thumbnail'];
  if (thumb is Map && thumb['thumbnails'] is List) {
    final list = thumb['thumbnails'] as List;
    if (list.isNotEmpty && list.last is Map) {
      var url = (list.last as Map)['url']?.toString() ?? '';
      if (url.startsWith('//')) url = 'https:$url';
      return url;
    }
  }
  return '';
}
