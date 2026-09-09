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

/// KMEP core data models.
/// Один файл для старта — как модели разрастутся, режем на отдельные файлы,
/// но пока удобнее держать вместе.
library;

class KMEPStream {
  final String url;
  final String quality; // "1080p", "720p", "audio", "adaptive" (для HLS live)
  final String codec;
  final String type; // "video" | "audio" | "hls"
  final int itag;
  final int? width;
  final int? height;
  final int? bitrate;
  final String mimeType;
  final bool isLive;

  const KMEPStream({
    required this.url,
    required this.quality,
    required this.codec,
    required this.type,
    required this.itag,
    required this.mimeType,
    this.width,
    this.height,
    this.bitrate,
    this.isLive = false,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'quality': quality,
        'codec': codec,
        'type': type,
        'itag': itag,
        'width': width,
        'height': height,
        'bitrate': bitrate,
        'mimeType': mimeType,
        'isLive': isLive,
      };
}

class VideoInfo {
  final String videoId;
  final String title;
  final String description;
  final int durationSeconds;
  final int viewCount;
  final String? publishDate;
  final String channelId;
  final String channelName;
  final String? channelAvatar;
  final List<String> thumbnails;
  final List<String> tags;
  final String? category;
  final int? likes;
  final bool isLive;
  final List<KMEPStream> streams;
  final String? hlsManifestUrl;

  const VideoInfo({
    required this.videoId,
    required this.title,
    required this.description,
    required this.durationSeconds,
    required this.viewCount,
    required this.channelId,
    required this.channelName,
    required this.thumbnails,
    required this.tags,
    required this.streams,
    this.publishDate,
    this.channelAvatar,
    this.category,
    this.likes,
    this.isLive = false,
    this.hlsManifestUrl,
  });
}

class ChannelInfo {
  final String channelId;
  final String name;
  final String? handle;
  final List<String> avatars;
  final String? banner;
  final int? subscriberCount;
  final int? videoCount;
  final String description;
  final List<String> links;
  final List<String> tabs;
  final String? primaryLinkId;

  const ChannelInfo({
    required this.channelId,
    required this.name,
    required this.avatars,
    required this.description,
    required this.links,
    required this.tabs,
    this.handle,
    this.banner,
    this.subscriberCount,
    this.videoCount,
    this.primaryLinkId,
  });
}

/// One page of a channel's video tab (or shorts/live tab). Videos come
/// as lightweight [VideoSearchResult] cards; [continuation] paginates.
class ChannelVideosPage {
  final List<VideoSearchResult> videos;
  final String? continuation;
  const ChannelVideosPage({required this.videos, this.continuation});
}

/// A YouTube playlist: header metadata plus the first page of videos.
/// Paginate the item list with [continuation].
class PlaylistInfo {
  final String playlistId;
  final String title;
  final String description;
  final String channelId;
  final String channelName;
  final String? channelAvatarUrl;
  final int videoCount;
  final String viewCountText;
  final List<VideoSearchResult> videos;
  final String? continuation;

  const PlaylistInfo({
    required this.playlistId,
    required this.title,
    required this.description,
    required this.channelId,
    required this.channelName,
    required this.videoCount,
    required this.viewCountText,
    required this.videos,
    this.channelAvatarUrl,
    this.continuation,
  });
}

/// One page of a playlist's videos, as lightweight cards.
class PlaylistVideosPage {
  final List<VideoSearchResult> videos;
  final String? continuation;
  const PlaylistVideosPage({required this.videos, this.continuation});
}

/// One page of comments for a video. [items] are top-level threads;
/// each thread's [CommentInfo.replies] contains the first batch of
/// replies YouTube sends inline (often empty until you fetch the
/// replies continuation — see [CommentInfo.repliesContinuation]).
class CommentsPage {
  final List<CommentInfo> items;
  final String? continuation;
  const CommentsPage({required this.items, this.continuation});
}

class CommentInfo {
  final String commentId;
  final String authorName;
  final String authorChannelId;
  final String? authorAvatar;
  final String text;
  final int likeCount;
  final int replyCount;
  final bool isHearted;
  final bool isPinned;
  final bool isVerifiedAuthor;
  final String? publishedTime;
  final List<CommentInfo> replies;

  /// Opaque continuation token to fetch MORE replies for this thread —
  /// pass it to `Kmep.getCommentReplies`. Null when YouTube sent all
  /// replies inline (or there are none).
  final String? repliesContinuation;

  const CommentInfo({
    required this.commentId,
    required this.authorName,
    required this.authorChannelId,
    required this.text,
    required this.likeCount,
    required this.replyCount,
    this.authorAvatar,
    this.isHearted = false,
    this.isPinned = false,
    this.isVerifiedAuthor = false,
    this.publishedTime,
    this.replies = const [],
    this.repliesContinuation,
  });
}

/// Lightweight video card as returned by search/shorts-feed — this is
/// what YouTube's own search results give you (no streams, no full
/// description). Call [Kmep.getVideo] with [videoId] if you need the
/// full [VideoInfo] with resolved streams.
class VideoSearchResult {
  final String videoId;
  final String title;
  final String channelName;
  final int durationSeconds;
  final int viewCount;
  final String thumbnailUrl;
  final String uploadDate;
  final bool isShort;

  const VideoSearchResult({
    required this.videoId,
    required this.title,
    required this.channelName,
    required this.durationSeconds,
    required this.viewCount,
    required this.thumbnailUrl,
    required this.uploadDate,
    this.isShort = false,
  });

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'channelName': channelName,
        'durationSeconds': durationSeconds,
        'viewCount': viewCount,
        'thumbnailUrl': thumbnailUrl,
        'uploadDate': uploadDate,
        'isShort': isShort,
      };
}

class SearchResultPage {
  final List<VideoSearchResult> results;
  final String? continuation;
  final int? estimatedResults;

  const SearchResultPage({
    required this.results,
    this.continuation,
    this.estimatedResults,
  });
}

/// Коды ошибок из спецификации KMEP §10.
enum KMEPErrorCode {
  ok,
  partial,
  nsigFail,
  poRequired,
  potFail,
  sabrOnly,
  unavailable,
  channelUnavailable,
  commentsUnavailable,
  searchUnavailable,
  rateLimited,
  networkError,
  parseError,
  playlistUnavailable,
}

class KMEPException implements Exception {
  final KMEPErrorCode code;
  final String message;
  final String? clientId; // какой клиент словил ошибку
  final Object? cause;

  const KMEPException(this.code, this.message, {this.clientId, this.cause});

  @override
  String toString() => 'KMEPException($code, client=$clientId): $message';
}
