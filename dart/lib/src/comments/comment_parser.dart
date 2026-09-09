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

import '../models/kmep_models.dart';

/// The pure parsing half of comment extraction: watch-next response ->
/// continuation tokens, comment page response -> [CommentsPage].
/// Kept separate from [CommentClient] so it's testable without network.

/// Finds the comment-section continuation token(s) inside a watch-next
/// (`/next` by videoId) response. Returns up to two tokens: the first
/// is the default ("Top comments") ordering, the second — "Newest
/// first", when YouTube sends both.
List<String> findCommentSectionTokens(Map<String, dynamic> watchNext) {
  final tokens = <String>[];

  void walk(dynamic node, int depth) {
    if (depth > 16 || node == null || tokens.length >= 2) return;
    if (node is Map) {
      final sec = node['itemSectionRenderer'];
      if (sec is Map && sec['sectionIdentifier'] == 'comment-item-section') {
        final contents = sec['contents'];
        if (contents is List) {
          for (final c in contents) {
            final t = _tokenOf(c);
            if (t != null && !tokens.contains(t)) tokens.add(t);
          }
        }
      }
      // Резерв: engagement panel (сортировка может прилетать и туда).
      final panel = node['engagementPanelSectionListRenderer'];
      if (panel is Map && panel['panelIdentifier'] == 'comment-item-section') {
        _walkForTokens(panel, tokens);
      }
      for (final v in node.values) {
        walk(v, depth + 1);
      }
    } else if (node is List) {
      for (final v in node) {
        walk(v, depth + 1);
      }
    }
  }

  walk(watchNext, 0);
  return tokens;
}

String? _tokenOf(dynamic item) {
  if (item is! Map) return null;
  final cont = item['continuationItemRenderer'];
  if (cont is Map) {
    final t = cont['continuationEndpoint']?['continuationCommand']?['token'];
    if (t is String && t.isNotEmpty) return t;
  }
  return null;
}

void _walkForTokens(dynamic node, List<String> out) {
  if (out.length >= 2) return;
  if (node is Map) {
    final t = _tokenOf(node);
    if (t != null) out.add(t);
    for (final v in node.values) {
      _walkForTokens(v, out);
    }
  } else if (node is List) {
    for (final v in node) {
      _walkForTokens(v, out);
    }
  }
}

/// Parses a comment-page response (a `/next` call with a continuation
/// token) into a typed [CommentsPage]. Handles both the legacy
/// `commentRenderer` shape and the current `commentViewModel` +
/// `frameworkUpdates.entityBatchUpdate` shape YouTube serves today.
CommentsPage parseCommentsPage(Map<String, dynamic> resp) {
  final items = <CommentInfo>[];
  String? nextContinuation;
  final threadsSeen = <String>{};

  // 1) Достаём «плоский» список comment-мутаций (новая модель данных).
  final payloads = <String, Map<String, dynamic>>{};
  final toolbars = <String, Map<String, dynamic>>{};
  final mutations =
      resp['frameworkUpdates']?['entityBatchUpdate']?['mutations'];
  if (mutations is List) {
    for (final m in mutations) {
      if (m is! Map) continue;
      final payload = m['payload'];
      if (payload is! Map) continue;
      final cep = payload['commentEntityPayload'];
      if (cep is Map) {
        final key = cep['key']?.toString();
        final id = cep['properties']?['commentId']?.toString();
        if (key != null && id != null) {
          payloads[id] = cep.cast<String, dynamic>();
        }
      }
      final ets = payload['engagementToolbarStateEntityPayload'];
      if (ets is Map) {
        final key = ets['key']?.toString();
        if (key != null) toolbars[key] = ets.cast<String, dynamic>();
      }
    }
  }

  // 2) Идём по элементам страницы: commentThreadRenderer (threads) или
  //    комментарий-компоненты продолжения.
  final pageItems = <Map<String, dynamic>>[];

  void collect(dynamic node, int depth) {
    if (depth > 16 || node == null) return;
    if (node is Map) {
      if (node['commentThreadRenderer'] is Map ||
          node['commentViewModel'] is Map) {
        pageItems.add(node.cast<String, dynamic>());
      }
      final cont = node['continuationItemRenderer'];
      if (cont is Map) {
        final t = _tokenOf({'continuationItemRenderer': cont});
        if (t != null) nextContinuation = t;
      }
      for (final v in node.values) {
        collect(v, depth + 1);
      }
    } else if (node is List) {
      for (final v in node) {
        collect(v, depth + 1);
      }
    }
  }

  collect(resp['onResponseReceivedEndpoints'] ?? resp, 0);

  // 3) Thread items: commentViewModel (id + pinned) + entity payload
  //    (author/text/likes) + replies continuation.
  for (final item in pageItems) {
    final thread = item['commentThreadRenderer'];
    Map<String, dynamic>? vm;
    Map<String, dynamic>? replies;

    if (thread is Map) {
      vm = _unwrapCommentViewModel(thread['commentViewModel']);
      replies = thread['replies']?['commentRepliesRenderer'] is Map
          ? thread['replies']['commentRepliesRenderer'].cast<String, dynamic>()
          : null;
    } else {
      vm = _unwrapCommentViewModel(item['commentViewModel']);
    }

    if (vm == null) continue;

    final commentId = vm['commentId']?.toString() ?? '';
    if (commentId.isEmpty || !threadsSeen.add(commentId)) continue;

    final payload = payloads[commentId];
    if (payload == null) continue; // мутации пришли не для этого page

    String? repliesToken;
    if (replies != null) {
      final contents = replies['contents'];
      if (contents is List) {
        for (final c in contents) {
          final t = _tokenOf(c);
          if (t != null) repliesToken = t;
        }
      }
      // "N replies" кнопка тоже носит continuationEndpoint.
      if (repliesToken == null) {
        void findToken(dynamic n, int depth) {
          if (repliesToken != null || depth > 8 || n == null) return;
          if (n is Map) {
            final t = _tokenOf(n);
            if (t != null) repliesToken = t;
            for (final v in n.values) {
              findToken(v, depth + 1);
            }
          } else if (n is List) {
            for (final v in n) {
              findToken(v, depth + 1);
            }
          }
        }

        findToken(replies, 0);
      }
    }

    items.add(_threadFromPayload(vm, payload, toolbars, repliesToken));
  }

  // 4) Легаси-рендерер (старый формат, если YouTube вернёт его).
  if (items.isEmpty) {
    void walkLegacy(dynamic node, int depth) {
      if (depth > 16 || node == null) return;
      if (node is Map) {
        final cr = node['commentRenderer'];
        if (cr is Map) {
          final item = _legacyComment(cr.cast<String, dynamic>());
          if (item != null && threadsSeen.add(item.commentId)) {
            items.add(item);
          }
        }
        final cont = node['continuationItemRenderer'];
        if (cont is Map) {
          final t = _tokenOf({'continuationItemRenderer': cont});
          if (t != null) nextContinuation = t;
        }
        for (final v in node.values) {
          walkLegacy(v, depth + 1);
        }
      } else if (node is List) {
        for (final v in node) {
          walkLegacy(v, depth + 1);
        }
      }
    }

    walkLegacy(resp['onResponseReceivedEndpoints'] ?? resp, 0);
  }

  return CommentsPage(items: items, continuation: nextContinuation);
}

CommentInfo _threadFromPayload(
  Map<String, dynamic> vm,
  Map<String, dynamic> payload, [
  Map<String, Map<String, dynamic>> toolbars = const {},
  String? repliesToken,
]) {
  final props = payload['properties'] ?? const {};
  final author = payload['author'] ?? const {};
  final toolbar = payload['toolbar'] ?? const {};

  final pinned = vm['pinnedText'] != null;

  var isHearted = false;
  final tsKey = vm['toolbarStateKey']?.toString();
  final ets = toolbars[tsKey];
  if (ets?['heartState'] == 'TOOLBAR_HEART_STATE_HEARTED') isHearted = true;

  // heartState также виден по наличию creatorThumbnail в toolbar.
  if (!isHearted && toolbar['creatorThumbnailUrl'] != null) isHearted = true;

  return CommentInfo(
    commentId:
        props['commentId']?.toString() ?? vm['commentId']?.toString() ?? '',
    authorName: author['displayName']?.toString() ?? '',
    authorChannelId: author['channelId']?.toString() ?? '',
    authorAvatar: author['avatarThumbnailUrl']?.toString(),
    text: props['content']?['content']?.toString() ?? '',
    likeCount: _compactCount(toolbar['likeCountLiked']?.toString()),
    replyCount: _compactCount(toolbar['replyCount']?.toString()),
    isHearted: isHearted,
    isPinned: pinned,
    isVerifiedAuthor: author['isVerified'] == true,
    publishedTime: props['publishedTime']?.toString(),
    replies: const [],
    repliesContinuation: repliesToken,
  );
}

CommentInfo? _legacyComment(Map<String, dynamic> r) {
  final id = r['commentId']?.toString();
  if (id == null || id.isEmpty) return null;

  String? authorChannelId;
  final authorEndpoint = r['authorEndpoint']?['browseEndpoint'];
  if (authorEndpoint is Map) {
    authorChannelId = authorEndpoint['browseId']?.toString();
  }

  var isHearted = false;
  final actionButtons = r['actionButtons']?['commentActionButtonsRenderer'];
  if (actionButtons is Map) {
    _walkAny(actionButtons, (n) {
      if (n['creatorHeart'] != null) isHearted = true;
    });
  }

  String? repliesToken;
  final replies = r['replies']?['commentRepliesRenderer'];
  if (replies is Map) {
    _walkAny(replies, (n) {
      final t = _tokenOf(n);
      if (t != null && repliesToken == null) repliesToken = t;
    });
  }

  return CommentInfo(
    commentId: id,
    authorName: r['authorText']?['simpleText']?.toString() ?? '',
    authorChannelId: authorChannelId ?? '',
    authorAvatar: _legacyAvatar(r),
    text: _legacyText(r['contentText']),
    likeCount: _compactCount(r['voteCount']?['simpleText']?.toString()),
    replyCount: 0,
    isHearted: isHearted,
    isPinned: r['pinnedCommentBadge'] != null,
    isVerifiedAuthor: r['authorCommentBadge'] != null,
    publishedTime: r['publishedTimeText']?['simpleText']?.toString(),
    replies: const [],
    repliesContinuation: repliesToken,
  );
}

void _walkAny(dynamic node, void Function(Map<String, dynamic>) visit,
    [int depth = 0]) {
  if (depth > 10 || node == null) return;
  if (node is Map) {
    visit(node.cast<String, dynamic>());
    for (final v in node.values) {
      _walkAny(v, visit, depth + 1);
    }
  } else if (node is List) {
    for (final v in node) {
      _walkAny(v, visit, depth + 1);
    }
  }
}

/// commentThreadRenderer.commentViewModel приходит в ДВУХ формах
/// (A/B флат): прямой объект с commentId, или обёртка
/// `{commentViewModel: {...}}`. Разворачиваем до прямого объекта.
Map<String, dynamic>? _unwrapCommentViewModel(dynamic raw) {
  if (raw is! Map) return null;
  if (raw['commentId'] is String) return raw.cast<String, dynamic>();
  final inner = raw['commentViewModel'];
  if (inner is Map && inner['commentId'] is String) {
    return inner.cast<String, dynamic>();
  }
  return null;
}

String? _legacyAvatar(Map<String, dynamic> r) {
  final thumbs = r['authorThumbnail']?['thumbnails'];
  if (thumbs is List && thumbs.isNotEmpty) {
    return (thumbs.last as Map)['url']?.toString();
  }
  return null;
}

String _legacyText(dynamic contentText) {
  if (contentText is! Map) return '';
  final runs = contentText['runs'];
  if (runs is List) {
    final sb = StringBuffer();
    for (final r in runs) {
      if (r is Map) sb.write(r['text']?.toString() ?? '');
    }
    return sb.toString();
  }
  return contentText['simpleText']?.toString() ?? '';
}

/// `"313K"` / `"1.2M"` / `"963"` -> int.
int _compactCount(String? text) {
  if (text == null || text.isEmpty) return 0;
  final m = RegExp(r'([\d.,]+)\s*([KMB])?').firstMatch(text);
  if (m == null) return 0;
  final numStr = m.group(1)!.replaceAll(',', '.');
  final num = double.tryParse(numStr);
  if (num == null) return 0;
  final mult = switch (m.group(2)) {
    'K' => 1000,
    'M' => 1000000,
    'B' => 1000000000,
    _ => 1,
  };
  return (num * mult).round();
}
