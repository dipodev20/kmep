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
import '../search/search_client.dart' show runsText;

/// InnerTube `browse` params for channel tab selectors (protobuf,
/// base64) — the same ones YouTube's own tab chips send. Sorted by
/// upload date where a sort exists; the "Latest" chip default.
const String kChannelVideosTabNewest = 'EgZ2aWRlb3PyBgQKAjoA';
const String kChannelVideosTabPopular = 'EgZ2aWRlb3MYAyAAMAE%3D';
const String kChannelVideosTabOldest = 'EgZ2aWRlb3MYAyAAMAI%3D';
const String kChannelShortsTab = 'EgZzaG9ydHPyBgUKA5oBAA%3D%3D';
const String kChannelLiveTab = 'EgdzdHJlYW1z8gYECgJ6AA%3D%3D';

/// Channel and playlist extraction. Both ride the InnerTube `/browse`
/// endpoint (WEB client — no PO token, no player.js, same as search:
/// `/browse` is served to the unauthenticated web client reliably).
///
/// Get one of these from `Kmep.getChannel`, `Kmep.getChannelVideos`,
/// `Kmep.getPlaylist` — or standalone if you only need channel data.
class ChannelClient {
  final InnerTubeClient _client;

  ChannelClient({String hl = 'en', String gl = 'US'})
      : _hl = hl,
        _gl = gl,
        _client = InnerTubeClient(ClientRegistry.resolved('WEB'));

  final String _hl;
  final String _gl;

  /// Full channel metadata: title, handle, avatar, banner, subscriber
  /// and video counts, description, social links, available tabs.
  ///
  /// [channelId] is the `UC...` id. A `@handle` also works — YouTube
  /// resolves it server-side (browseId `@handle`), returning the same
  /// page; the returned [ChannelInfo.channelId] is then the canonical
  /// `UC...` id.
  Future<ChannelInfo> getChannel(String channelId) async {
    final resp = await _client.fetchBrowse(
      channelId.startsWith('UC') || channelId.startsWith('HC')
          ? channelId
          : channelId, // browseId принимает и @handle
      hl: _hl,
      gl: _gl,
    );
    final info = _parseChannelHeader(resp);
    if (info == null) {
      throw const KMEPException(
          KMEPErrorCode.channelUnavailable, 'channel page is empty');
    }
    return info;
  }

  /// One page of a channel's Videos tab, sorted by newest upload.
  /// Use [continuation] from the returned page for the next page.
  Future<ChannelVideosPage> getChannelVideos(
    String channelId, {
    String? continuation,
    String params = kChannelVideosTabNewest,
  }) async {
    final resp = await _client.fetchBrowse(
      channelId,
      params: continuation == null ? params : null,
      continuation: continuation,
      hl: _hl,
      gl: _gl,
    );
    final videos = <VideoSearchResult>[];
    String? nextToken;
    _walk(resp, (node) {
      // Новая структура (2025+): richGridRenderer → richItemRenderer →
      // lockupViewModel. Старая: gridRenderer → gridVideoRenderer.
      final lockup = node['lockupViewModel'];
      if (lockup is Map && lockup['contentId'] is String) {
        final item = _lockupToVideo(lockup.cast<String, dynamic>(),
            contentId: lockup['contentId'] as String);
        if (item != null) videos.add(item);
      }
      final gridVideo = node['gridVideoRenderer'];
      if (gridVideo is Map) {
        final item = _gridVideoToItem(gridVideo.cast<String, dynamic>());
        if (item != null) videos.add(item);
      }
      final cont = node['continuationItemRenderer'];
      if (cont is Map) {
        final t = _continuationToken(cont);
        if (t != null) nextToken = t;
      }
    });
    if (videos.isEmpty && continuation == null) {
      throw const KMEPException(
          KMEPErrorCode.channelUnavailable, 'channel videos page is empty');
    }
    return ChannelVideosPage(videos: videos, continuation: nextToken);
  }

  /// A playlist's metadata plus its first page of videos. Works with
  /// normal (`PL...`) and mixed (`OL...`/`VL...` radio) playlists.
  ///
  /// [playlistId] accepts the bare id; a full watch URL
  /// (`...watch?v=...&list=PL...`) is also tolerated — the id is
  /// extracted from it.
  Future<PlaylistInfo> getPlaylist(String playlistId) async {
    final id = _extractPlaylistId(playlistId);
    final resp = await _client.fetchBrowse('VL$id', hl: _hl, gl: _gl);
    return _parsePlaylist(id, resp);
  }

  /// Next page of a playlist's videos (pass the continuation token
  /// returned by [getPlaylist] or a previous call to this).
  Future<PlaylistVideosPage> getPlaylistVideos(
      String playlistId, String continuation) async {
    final id = _extractPlaylistId(playlistId);
    final resp = await _client.fetchBrowse('VL$id',
        continuation: continuation, hl: _hl, gl: _gl);
    final videos = <VideoSearchResult>[];
    String? nextToken;
    _walk(resp, (node) {
      final lockup = node['lockupViewModel'];
      if (lockup is Map && lockup['contentId'] is String) {
        final item = _lockupToVideo(lockup.cast<String, dynamic>(),
            contentId: lockup['contentId'] as String);
        if (item != null) videos.add(item);
      }
      final plv = node['playlistVideoRenderer'];
      if (plv is Map) {
        final item = _playlistVideoToItem(plv.cast<String, dynamic>());
        if (item != null) videos.add(item);
      }
      final cont = node['continuationItemRenderer'];
      if (cont is Map) {
        final t = _continuationToken(cont);
        if (t != null) nextToken = t;
      }
    });
    return PlaylistVideosPage(videos: videos, continuation: nextToken);
  }

  void close() => _client.close();

  // ---- test hooks -----------------------------------------------------------
  // Парсеры — чистые функции над ответом InnerTube; открыты для юнит-тестов
  // (мокировать сеть ради проверки парсинга не нужно).

  ChannelInfo? testParseChannelHeader(Map<String, dynamic> resp) =>
      _parseChannelHeader(resp);

  ChannelVideosPage testParseChannelVideos(Map<String, dynamic> resp) {
    final videos = <VideoSearchResult>[];
    String? nextToken;
    _walk(resp, (node) {
      final lockup = node['lockupViewModel'];
      if (lockup is Map && lockup['contentId'] is String) {
        final item = _lockupToVideo(lockup.cast<String, dynamic>(),
            contentId: lockup['contentId'] as String);
        if (item != null) videos.add(item);
      }
      final gridVideo = node['gridVideoRenderer'];
      if (gridVideo is Map) {
        final item = _gridVideoToItem(gridVideo.cast<String, dynamic>());
        if (item != null) videos.add(item);
      }
      final cont = node['continuationItemRenderer'];
      if (cont is Map) {
        final t = _continuationToken(cont);
        if (t != null) nextToken = t;
      }
    });
    return ChannelVideosPage(videos: videos, continuation: nextToken);
  }

  PlaylistInfo testParsePlaylist(
          String playlistId, Map<String, dynamic> resp) =>
      _parsePlaylist(playlistId, resp);

  // ---- parsing -------------------------------------------------------------

  /// Recursively visits every Map in the response tree (depth-capped).
  /// Cheaper and more resilient than walking by hand: InnerTube nests
  /// lockups differently per surface and A/B experiment.
  static void _walk(dynamic node, void Function(Map<String, dynamic>) visit,
      [int depth = 0]) {
    if (depth > 16 || node == null) return;
    if (node is Map) {
      final map = node.cast<String, dynamic>();
      visit(map);
      for (final v in map.values) {
        _walk(v, visit, depth + 1);
      }
    } else if (node is List) {
      for (final v in node) {
        _walk(v, visit, depth + 1);
      }
    }
  }

  static String? _continuationToken(Map cont) {
    try {
      final t = cont['continuationEndpoint']?['continuationCommand']?['token'];
      return t is String && t.isNotEmpty ? t : null;
    } catch (_) {
      return null;
    }
  }

  ChannelInfo? _parseChannelHeader(Map<String, dynamic> resp) {
    final vm = _channelHeaderVm(resp);
    if (vm == null) return null;
    final title =
        vm['title']?['dynamicTextViewModel']?['text']?['content']?.toString() ??
            resp['metadata']?['channelMetadataRenderer']?['title']?.toString();
    if (title == null || title.isEmpty) return null;

    final meta = resp['metadata']?['channelMetadataRenderer'];
    String? channelId = (meta?['externalId'] ?? meta?['channelUrl'])
        ?.toString()
        .replaceFirst(RegExp(r'^.*/channel/'), '');
    channelId ??= _browseIdFromHeader(vm) ?? '';

    var handle = '';
    var description = '';
    var subscriberCount = 0;
    var videoCount = 0;
    final rows =
        vm['metadata']?['contentMetadataViewModel']?['metadataRows'] as List?;
    if (rows != null) {
      for (final row in rows) {
        final parts = (row as Map)['metadataParts'] as List?;
        if (parts == null) continue;
        for (final p in parts) {
          final text = (p as Map)['text']?['content']?.toString() ?? '';
          if (text.startsWith('@')) handle = text;
          if (text.contains('subscriber')) {
            subscriberCount = _countFromText(text);
          }
          if (text.contains('video')) {
            videoCount = _countFromText(text);
          }
        }
      }
    }
    final descVm = vm['description']?['descriptionPreviewViewModel']
        ?['description']?['content'];
    if (descVm is String) description = descVm;
    if (description.isEmpty) {
      description = meta?['description']?.toString() ?? '';
    }

    final avatars = <String>[];
    final avatarSources = vm['image']?['decoratedAvatarViewModel']?['avatar']
        ?['avatarViewModel']?['image']?['sources'];
    if (avatarSources is List) {
      for (final s in avatarSources) {
        final url = (s as Map)['url']?.toString();
        if (url != null && url.isNotEmpty) avatars.add(url);
      }
    }
    if (avatars.isEmpty) {
      final t = meta?['avatar']?['thumbnails'];
      if (t is List) {
        for (final s in t) {
          final url = (s as Map)['url']?.toString();
          if (url != null && url.isNotEmpty) avatars.add(url);
        }
      }
    }

    var banner = '';
    final bannerSources =
        vm['banner']?['imageBannerViewModel']?['image']?['sources'];
    if (bannerSources is List && bannerSources.isNotEmpty) {
      final last = bannerSources.last;
      if (last is Map) banner = last['url']?.toString() ?? '';
    }
    // Старый bannerRenderer (не-A/B) — тоже поддержим.
    if (banner.isEmpty) {
      _walk(resp, (node) {
        if (banner.isEmpty) {
          final b = node['bannerRenderer'];
          if (b is Map) {
            _walk(b, (n) {
              final srcs = n['sources'];
              if (srcs is List && srcs.isNotEmpty && banner.isEmpty) {
                final url = (srcs.last as Map)['url']?.toString();
                if (url != null) banner = url;
              }
            });
          }
        }
      });
    }

    // Соц-ссылки: attributionViewModel + старый aboutSecondaryInfoRenderer.
    final links = <String>[];
    final attr = vm['attribution']?['attributionViewModel'];
    if (attr != null) {
      _walk(attr, (node) {
        final cmd = node['innertubeCommand']?['urlEntityCommand']?['url'];
        if (cmd is String && cmd.startsWith('http')) links.add(cmd);
      });
    }
    if (links.isEmpty) {
      final about = resp['secondarySearchChannelRenderer'];
      _walk(about, (node) {
        final l = node['channelExternalLinkViewModel'];
        if (l is Map) {
          final link = l['link']?['content']?.toString();
          if (link != null && link.isNotEmpty) links.add(link);
        }
      });
    }

    final tabs = <String>[];
    _walk(resp['contents'], (node) {
      final t = node['tabRenderer'];
      if (t is Map && t['title'] is String) tabs.add(t['title'] as String);
    });

    return ChannelInfo(
      channelId: channelId,
      name: title,
      handle: handle.isEmpty ? null : handle,
      avatars: avatars,
      banner: banner.isEmpty ? null : banner,
      subscriberCount: subscriberCount,
      videoCount: videoCount,
      description: description,
      links: links,
      tabs: tabs,
      primaryLinkId: links.isEmpty ? null : links.first,
    );
  }

  static Map<String, dynamic>? _channelHeaderVm(Map<String, dynamic> resp) {
    final vm = resp['header']?['pageHeaderRenderer']?['content']
        ?['pageHeaderViewModel'];
    return vm is Map<String, dynamic> ? vm : null;
  }

  static String? _browseIdFromHeader(Map<String, dynamic> vm) {
    String? found;
    _walk(vm, (node) {
      if (found == null) {
        final be = node['browseEndpoint'];
        if (be is Map) {
          final id = be['browseId'];
          if (id is String && id.startsWith('UC')) found = id;
        }
      }
    });
    return found;
  }

  PlaylistInfo _parsePlaylist(String playlistId, Map<String, dynamic> resp) {
    final vm = resp['header']?['pageHeaderRenderer']?['content']
        ?['pageHeaderViewModel'];
    final title =
        vm?['title']?['dynamicTextViewModel']?['text']?['content'].toString() ??
            '';

    var videoCount = 0;
    var viewCountText = '';
    var lastUpdated = '';
    if (vm != null) {
      final rows = vm['metadata']?['contentMetadataViewModel']?['metadataRows'];
      if (rows is List) {
        for (final row in rows) {
          final parts = (row as Map)['metadataParts'];
          if (parts is! List) continue;
          for (final p in parts) {
            final text = (p as Map)['text']?['content']?.toString() ?? '';
            if (text.contains('video')) videoCount = _countFromText(text);
            if (text.contains('view')) viewCountText = text;
            if (text.toLowerCase().contains('updated')) lastUpdated = text;
          }
        }
      }
    }
    // Fallback: старый sidebar (не-A/B).
    if (videoCount == 0) {
      final stats = resp['sidebar']?['playlistSidebarRenderer']?['items'];
      if (stats is List) {
        for (final it in stats) {
          final prim = (it as Map)['playlistSidebarPrimaryInfoRenderer'];
          if (prim is Map) {
            final st = prim['stats'];
            if (st is List) {
              for (final s in st) {
                final text = runsText(s);
                if (text != null && text.contains('video')) {
                  videoCount = _countFromText(text);
                }
              }
            }
          }
        }
      }
    }

    var channelId = '';
    var channelName = '';
    var channelAvatar = '';
    if (vm != null) {
      _walk(vm['metadata'], (node) {
        if (channelId.isEmpty) {
          final be = node['innertubeCommand']?['browseEndpoint'] ??
              node['browseEndpoint'];
          if (be is Map && be['browseId'] is String) {
            final id = be['browseId'] as String;
            if (id.startsWith('UC')) {
              channelId = id;
              final text = node['text']?['content']?.toString() ?? '';
              if (text.startsWith('by ')) channelName = text.substring(3);
            }
          }
        }
      });
    }
    if (channelId.isEmpty || channelName.isEmpty) {
      final sec = resp['sidebar']?['playlistSidebarRenderer']?['items'];
      if (sec is List) {
        for (final it in sec) {
          final owner = (it as Map)['playlistSidebarSecondaryInfoRenderer']
              ?['videoOwner']?['videoOwnerRenderer'];
          if (owner is Map) {
            if (channelName.isEmpty) {
              channelName = runsText(owner['title']) ?? '';
            }
            if (channelId.isEmpty) {
              channelId = owner['navigationEndpoint']?['browseEndpoint']
                          ?['browseId']
                      ?.toString() ??
                  '';
            }
            if (channelAvatar.isEmpty) {
              final t = owner['thumbnail']?['thumbnails'];
              if (t is List && t.isNotEmpty) {
                channelAvatar = (t.last as Map)['url']?.toString() ?? '';
              }
            }
          }
        }
      }
    }
    if (channelAvatar.isEmpty && vm != null) {
      _walk(vm['metadata'], (node) {
        if (channelAvatar.isEmpty) {
          final srcs = node['avatarViewModel']?['image']?['sources'];
          if (srcs is List && srcs.isNotEmpty) {
            channelAvatar = (srcs.last as Map)['url']?.toString() ?? '';
          }
        }
      });
    }

    var description = '';
    // Playlist descriptions живут в микроданных страницы; InnerTube
    // отдаёт их не всегда — оставляем пустыми, если нет.

    final videos = <VideoSearchResult>[];
    String? continuation;
    _walk(resp['contents'], (node) {
      final lockup = node['lockupViewModel'];
      if (lockup is Map && lockup['contentId'] is String) {
        final item = _lockupToVideo(lockup.cast<String, dynamic>(),
            contentId: lockup['contentId'] as String);
        if (item != null) videos.add(item);
      }
      final plv = node['playlistVideoRenderer'];
      if (plv is Map) {
        final item = _playlistVideoToItem(plv.cast<String, dynamic>());
        if (item != null) videos.add(item);
      }
      final cont = node['continuationItemRenderer'];
      if (cont is Map) {
        final t = _continuationToken(cont);
        // Берём ПЕРВЫЙ токен: у плейлистов их два — настоящий
        // (внутри itemSectionRenderer, после последнего видео) и
        // «сигнальный» хвостовой (sectionListRenderer.contents[N]),
        // на который YouTube отвечает пустой страницей.
        if (t != null && continuation == null) continuation = t;
      }
    });

    return PlaylistInfo(
      playlistId: playlistId,
      title: title,
      description: description,
      channelId: channelId,
      channelName: channelName,
      channelAvatarUrl: channelAvatar.isEmpty ? null : channelAvatar,
      videoCount: videoCount,
      viewCountText:
          '$viewCountText${lastUpdated.isEmpty ? '' : ' · $lastUpdated'}'
              .trim(),
      videos: videos,
      continuation: continuation,
    );
  }

  /// `lockupViewModel` (современный рендерер видео-карточек в browse:
  /// канал/плейлист) -> [VideoSearchResult]. Duration живёт в
  /// thumbnail-badge overlay, views/date — в metadata rows.
  static VideoSearchResult? _lockupToVideo(Map<String, dynamic> lockup,
      {required String contentId}) {
    if (contentId.isEmpty) return null;

    var title = '';
    var viewsText = '';
    var dateText = '';
    final md = lockup['metadata']?['lockupMetadataViewModel'];
    if (md is Map) {
      title = md['title']?['content']?.toString() ?? '';
      final rows = md['metadata']?['contentMetadataViewModel']?['metadataRows'];
      if (rows is List) {
        for (final row in rows) {
          final parts = (row as Map)['metadataParts'];
          if (parts is! List) continue;
          for (final p in parts) {
            final text = (p as Map)['text']?['content']?.toString() ?? '';
            if (text.contains('view') && viewsText.isEmpty) viewsText = text;
            if (text.toLowerCase().contains('ago') && dateText.isEmpty) {
              dateText = text;
            }
          }
        }
      }
    }

    var duration = 0;
    var thumb = '';
    final thumbVm = lockup['contentImage']?['thumbnailViewModel'];
    if (thumbVm is Map) {
      final srcs = thumbVm['image']?['sources'];
      if (srcs is List && srcs.isNotEmpty) {
        thumb = (srcs.last as Map)['url']?.toString() ?? '';
      }
      final overlays = thumbVm['overlays'];
      if (overlays is List) {
        for (final o in overlays) {
          final badges =
              (o as Map)['thumbnailBottomOverlayViewModel']?['badges'];
          if (badges is List) {
            for (final b in badges) {
              final badge = (b as Map)['thumbnailBadgeViewModel'];
              if (badge is Map) {
                final t = badge['text']?.toString() ?? '';
                final d = _durationFromBadge(t);
                if (d > 0) duration = d;
              }
            }
          }
        }
      }
    }
    if (thumb.startsWith('//')) thumb = 'https:$thumb';

    return VideoSearchResult(
      videoId: contentId,
      title: title,
      channelName: '',
      durationSeconds: duration,
      viewCount: viewsText.isEmpty ? 0 : _countFromText(viewsText),
      thumbnailUrl: thumb,
      uploadDate: dateText,
    );
  }

  /// Старый `gridVideoRenderer` -> карточка.
  static VideoSearchResult? _gridVideoToItem(Map<String, dynamic> r) {
    final id = r['videoId']?.toString();
    if (id == null || id.isEmpty) return null;
    return VideoSearchResult(
      videoId: id,
      title: runsText(r['title']) ?? '',
      channelName: '',
      durationSeconds: _durationFromBadge(runsText(r['lengthText']) ?? ''),
      viewCount: _countFromText(runsText(r['viewCountText']) ?? ''),
      thumbnailUrl: _lastThumbnail(r),
      uploadDate: runsText(r['publishedTimeText']) ?? '',
    );
  }

  /// Старый `playlistVideoRenderer` -> карточка.
  static VideoSearchResult? _playlistVideoToItem(Map<String, dynamic> r) {
    final id = r['videoId']?.toString();
    if (id == null || id.isEmpty) return null;
    return VideoSearchResult(
      videoId: id,
      title: runsText(r['title']) ?? '',
      channelName: runsText(r['shortBylineText']) ?? '',
      durationSeconds: int.tryParse(r['lengthSeconds']?.toString() ?? '') ?? 0,
      viewCount: 0,
      thumbnailUrl: _lastThumbnail(r),
      uploadDate: '',
    );
  }

  static String _lastThumbnail(Map<String, dynamic> r) {
    final t = r['thumbnail']?['thumbnails'];
    if (t is List && t.isNotEmpty) {
      var url = (t.last as Map)['url']?.toString() ?? '';
      if (url.startsWith('//')) url = 'https:$url';
      return url;
    }
    return '';
  }

  /// `"3:55"` / `"1:02:03"` -> seconds. Badge duration format.
  static int _durationFromBadge(String text) {
    final parts = text.split(':');
    if (parts.isEmpty || parts.length > 3) return 0;
    var seconds = 0;
    for (final p in parts) {
      final v = int.tryParse(p.trim());
      if (v == null) return 0;
      seconds = seconds * 60 + v;
    }
    return seconds;
  }

  /// `"109M subscribers"` / `"4.6K videos"` -> int. Suffixes: K/M/B.
  static int _countFromText(String text) {
    final m = RegExp(r'([\d.,]+)\s*([KMB])?').firstMatch(text);
    if (m == null) return 0;
    final numStr = m.group(1)!.replaceAll(',', '.');
    final num = double.tryParse(numStr);
    if (num == null) return 0;
    final suffix = m.group(2);
    final mult = switch (suffix) {
      'K' => 1000,
      'M' => 1000000,
      'B' => 1000000000,
      _ => 1,
    };
    return (num * mult).round();
  }

  static String _extractPlaylistId(String input) {
    final m = RegExp(r'list=([A-Za-z0-9_\-]+)').firstMatch(input);
    if (m != null) return m.group(1)!;
    return input;
  }
}

/// Temporary debug helper.
class ChannelDebug {
  static void walkTest(
      dynamic node, void Function(Map<String, dynamic>) visit) {
    ChannelClient._walk(node, visit);
  }
}
