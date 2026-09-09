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

import 'channel/channel_client.dart';
import 'comments/comment_client.dart';
import 'core/botguard_pot_provider.dart';
import 'core/cache_manager.dart';
import 'core/extraction_orchestrator.dart';
import 'core/po_token.dart';
import 'core/remote_config.dart';
import 'core/watch_page_meta.dart';
import 'models/kmep_models.dart';
import 'resolvers/stream_resolver.dart';
import 'search/search_client.dart';

/// The single entry point for KMEP.
///
/// KMEP needs two things from the host platform that plain Dart can't
/// provide on its own:
///
///  1. A [JsRuntime] — something that can execute YouTube's `player.js`
///     to reverse the `n`/signature transforms on stream URLs. On
///     Flutter, use `WebViewJsRuntime` from the `flutter_integration`
///     package (recommended — QuickJS-based runtimes are known to choke
///     on `player.js`); on a plain Dart/server target, use
///     `NodeProcessJsRuntime` if a `node` binary is available.
///  2. A way to fetch arbitrary URLs as text ([fetchText]) — kept
///     pluggable so you can reuse whatever HTTP client/interceptors
///     your app already has (retry policy, proxy, logging, ...).
///
/// Everything else — client fallback order, caching, PO tokens, search —
/// has sane defaults and can be overridden via the named parameters.
///
/// ```dart
/// final kmep = Kmep(jsRuntime: myRuntime, fetchText: myHttpGetText);
/// final video = await kmep.getVideo('dQw4w9WgXcQ');
/// final results = await kmep.search('lofi hip hop');
/// ```
class Kmep {
  final ExtractionOrchestrator _orchestrator;
  final String hl;
  final String gl;

  /// Diagnostics: the reason the last PO token request failed, if any.
  /// Handy for a debug/settings screen ("last extractor error: ...").
  String? get lastPoTokenError =>
      _poTokenDiagnostics is BotGuardJsPoTokenProvider
          ? (_poTokenDiagnostics as BotGuardJsPoTokenProvider).lastError
          : null;
  final PoTokenProvider? _poTokenDiagnostics;

  factory Kmep({
    required JsRuntime jsRuntime,
    required Future<String> Function(String url) fetchText,
    String hl = 'en',
    String gl = 'US',
    RemoteConfig config = const RemoteConfig(),
    CacheManager? cache,
    PoTokenProvider? poTokenProvider,
    WatchPageMetaProvider? watchPageMetaProvider,
  }) {
    final metaProvider = CachedWatchPageMetaProvider(
      watchPageMetaProvider ?? HttpWatchPageMetaProvider(),
    );
    final orchestrator = ExtractionOrchestrator(
      config: config,
      cache: cache ?? InMemoryCacheManager(),
      poTokenProvider: poTokenProvider ?? const NoOpPoTokenProvider(),
      streamResolver:
          StreamResolver(jsRuntime: jsRuntime, fetchPlayerJs: fetchText),
      watchPageMetaProvider: metaProvider,
    );
    return Kmep._(orchestrator, poTokenProvider, hl, gl);
  }

  Kmep._(this._orchestrator, this._poTokenDiagnostics, this.hl, this.gl);

  /// Convenience factory that wires up on-device PO token generation
  /// (BotGuard, no external server needed) and shares one cached
  /// watch-page metadata provider between the orchestrator and the
  /// token provider's `visitorData` binding — avoids fetching the same
  /// watch page twice per video.
  ///
  /// [potJsRuntime] should be a *separate* [JsRuntime] instance from
  /// the one passed for stream resolution — running BotGuard and
  /// `player.js` in the same JS globals has caused cross-contamination
  /// in testing.
  factory Kmep.withOnDevicePoToken({
    required JsRuntime jsRuntime,
    required JsRuntime potJsRuntime,
    required Future<String> Function(String url) fetchText,
    String hl = 'en',
    String gl = 'US',
    RemoteConfig config = const RemoteConfig(),
    CacheManager? cache,
  }) {
    final metaProvider =
        CachedWatchPageMetaProvider(HttpWatchPageMetaProvider());
    final poTokenProvider = BotGuardJsPoTokenProvider(
      jsRuntime: potJsRuntime,
      fetchText: fetchText,
      bindingFor: (videoId) async =>
          (await metaProvider.fetch(videoId))?.visitorData,
    );
    return Kmep(
      jsRuntime: jsRuntime,
      fetchText: fetchText,
      hl: hl,
      gl: gl,
      config: config,
      cache: cache,
      poTokenProvider: poTokenProvider,
      watchPageMetaProvider: metaProvider,
    );
  }

  /// Resolves a video's metadata and playable stream URLs. Tries
  /// clients in [RemoteConfig.clientPriority] order and falls back
  /// automatically; throws [KMEPException] only if every client fails.
  Future<VideoInfo> getVideo(String videoId) =>
      _orchestrator.fetchVideo(videoId, hl: hl, gl: gl);

  /// Regular YouTube search. Does not require the JS runtime or PO
  /// token machinery — it's a plain InnerTube call.
  Future<SearchResultPage> search(String query, {String? continuation}) {
    final client = SearchClient(hl: hl, gl: gl);
    return client
        .search(query, continuation: continuation)
        .whenComplete(client.close);
  }

  /// One page of a Shorts-only feed for [query].
  Future<ShortsFeedPage> shortsFeed(
      {required String query, String? continuation}) {
    final client = SearchClient(hl: hl, gl: gl);
    return client
        .shortsFeed(query: query, continuation: continuation)
        .whenComplete(client.close);
  }

  /// Full channel metadata (title, handle, avatar, banner, subscriber /
  /// video counts, description, social links, available tabs).
  /// Accepts a `UC...` id or an `@handle`. No JS runtime or PO token
  /// needed — plain InnerTube `/browse`.
  Future<ChannelInfo> getChannel(String channelId) {
    final client = ChannelClient(hl: hl, gl: gl);
    return client.getChannel(channelId).whenComplete(client.close);
  }

  /// One page of a channel's Videos tab (newest first by default; see
  /// [ChannelClient] for other sort params). [continuation] paginates.
  Future<ChannelVideosPage> getChannelVideos(
    String channelId, {
    String? continuation,
    String params = kChannelVideosTabNewest,
  }) {
    final client = ChannelClient(hl: hl, gl: gl);
    return client
        .getChannelVideos(channelId, continuation: continuation, params: params)
        .whenComplete(client.close);
  }

  /// A playlist's metadata plus its first page of videos. [playlistId]
  /// can be a bare `PL...` id or a full watch URL with `list=`.
  Future<PlaylistInfo> getPlaylist(String playlistId) {
    final client = ChannelClient(hl: hl, gl: gl);
    return client.getPlaylist(playlistId).whenComplete(client.close);
  }

  /// Next page of a playlist's videos (continuation from [getPlaylist]
  /// or a previous call to this).
  Future<PlaylistVideosPage> getPlaylistVideos(
      String playlistId, String continuation) {
    final client = ChannelClient(hl: hl, gl: gl);
    return client
        .getPlaylistVideos(playlistId, continuation)
        .whenComplete(client.close);
  }

  /// First page of comments for a video. [sort] picks "top" (default)
  /// or "newest" ordering. No JS runtime or PO token needed.
  Future<CommentsPage> getComments(String videoId,
      {CommentSort sort = CommentSort.top}) {
    final client = CommentClient(hl: hl, gl: gl);
    return client.getComments(videoId, sort: sort).whenComplete(client.close);
  }

  /// Next page of comments (continuation from a previous [CommentsPage]).
  Future<CommentsPage> getCommentsByContinuation(String continuation) {
    final client = CommentClient(hl: hl, gl: gl);
    return client
        .getCommentsByContinuation(continuation)
        .whenComplete(client.close);
  }

  /// Replies for one comment thread — the continuation comes from
  /// [CommentInfo.repliesContinuation] of a thread returned by
  /// [getComments].
  Future<CommentsPage> getCommentReplies(String repliesContinuation) {
    final client = CommentClient(hl: hl, gl: gl);
    return client.getReplies(repliesContinuation).whenComplete(client.close);
  }
}
