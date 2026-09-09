# Changelog

## 0.3.0 — Channels, playlists, comments

The three big "not yet" items from 0.2.0 are done. All of them ride
the unauthenticated InnerTube WEB client (same as search — no JS
runtime, no PO token, no player.js), so they work on every platform
KMEP runs on, including plain Dart servers.

### Added
- **Channels** (`lib/src/channel/channel_client.dart`): full header
  metadata (title, handle, avatar, banner, subscriber/video counts,
  description, social links, available tabs) plus the Videos tab with
  pagination. Handles YouTube's current `pageHeaderViewModel` header
  shape and both the legacy `gridVideoRenderer` and current
  `lockupViewModel` video cards. Tab/sort params exported as constants
  (`kChannelVideosTabNewest/Popular/Oldest`, `kChannelShortsTab`,
  `kChannelLiveTab`).
- **Playlists**: header (title, owner, video count, view count, last
  updated) + videos with pagination, via the `VL...` browse id.
  Continuation handling picks the *first* token found — playlists
  carry two, and the trailing one is a signal-only stub that returns
  an empty page (found the hard way, live).
- **Comments** (`lib/src/comments/`): `/next`-based extraction with
  top/newest sort, page continuation, and per-thread replies
  continuation. Parses the current `commentViewModel` +
  `frameworkUpdates.entityBatchUpdate` data model (author, text,
  likes, reply count, pinned, creator-hearted, verified), including
  the A/B shape where `commentViewModel` arrives double-wrapped;
  falls back to the legacy `commentRenderer` shape. `CommentInfo`
  grew `isVerifiedAuthor` and `repliesContinuation`.
- `Kmep` facade methods for all of the above: `getChannel`,
  `getChannelVideos`, `getPlaylist`, `getPlaylistVideos`, `getComments`,
  `getCommentsByContinuation`, `getCommentReplies`.
- New models: `ChannelVideosPage`, `PlaylistInfo`, `PlaylistVideosPage`,
  `CommentsPage`; `KMEPErrorCode.playlistUnavailable`.
- Live-response fixtures (`test/fixtures/`) and 6 new unit tests —
  53 total, all green.
- `example/example.dart` now demonstrates the full surface end-to-end.
- **Package renamed `kmep_proto` → `kmep`** (see Breaking changes
  below); the on-device test harness moved to `kmep_harness/`.

## 0.2.0 — Public API pass

This release turns the internal prototype into something meant to be
depended on from outside Vidora. No extraction logic changed — the
InnerTube clients, `player.js` execution, and BotGuard PO token flow
are untouched and keep the ~98% success rate this prototype validated
in production. What changed is the *shape* of the library:

### Added
- **`Kmep` facade** (`lib/src/kmep_client.dart`) — one class to construct
  instead of wiring `ExtractionOrchestrator` + `StreamResolver` +
  `CachedWatchPageMetaProvider` + `BotGuardJsPoTokenProvider` by hand.
  `Kmep.withOnDevicePoToken(...)` is the one-call setup for the common
  case (on-device PO tokens, one shared cached watch-page provider).
- **Search and shorts feed are now part of the library**
  (`lib/src/search/search_client.dart`), typed as `VideoSearchResult` /
  `SearchResultPage` / `ShortsFeedPage` instead of raw
  `Map<String, dynamic>`. This logic previously lived duplicated in the
  Vidora app's platform-channel glue code; it's YouTube-extraction logic
  like everything else here, so it belongs in the library.
- **`CachedWatchPageMetaProvider`** — a small TTL-caching decorator for
  `WatchPageMetaProvider`. Previously each app integrating this library
  had to write its own (Vidora did). Promoted into the library so the
  fix isn't reinvented per consumer.
- **`BotGuardJsPoTokenProvider.bindingFor`** — an async
  `Future<String?> Function(String videoId)` alternative to the existing
  synchronous `bindingResolver`. The synchronous map-based API doesn't
  fit the common case of resolving the binding from a network call (e.g.
  `visitorData` from the watch page); `bindingFor` does, and is now what
  `Kmep.withOnDevicePoToken` uses internally.
- Curated public export surface in `lib/kmep.dart`, grouped by purpose
  (entry point / models / search / platform integration points /
  configuration / low-level building blocks) with doc comments on each
  group.
- Unit tests for the promoted search parser and the new cache decorator.
- Project branding (logo, cover) in `branding/`.

### Changed
- `SearchResultPage.results` is now `List<VideoSearchResult>` (was
  `List<dynamic>`).
- **License switched from MIT to GPLv3** (see below).

### License

Relicensed MIT → **GPL-3.0-or-later**, the same license as NewPipe.
This project is the result of weeks of reverse-engineering work —
on-device BotGuard PO token generation, multi-client InnerTube
fallback, real `player.js` execution — and the copyleft license keeps
it that way: anyone building on it must publish their changes under
GPLv3 too. Taking this code, renaming it and shipping it as a
closed-source "own" extractor is a copyright violation.

### Known gaps (tracked, not yet implemented)
- ~~No channel or playlist extraction~~ — **done in 0.3.0**.
- ~~No comments support~~ — **done in 0.3.0**.
- YouTube only — there is no NewPipe-style `StreamingService`
  abstraction for other sites. Multi-site support would be a 1.0-scope
  change, not a patch on top of this API.
- ~~Package still named `kmep_proto`~~ — **renamed to `kmep` in
  0.3.0** (pubspec, imports, harness folder). Publishing to pub.dev
  is a deliberate separate step.

### Breaking changes
- **Package renamed: `kmep_proto` → `kmep`.** Update your
  `pubspec.yaml` dependency and `import 'package:kmep/kmep.dart';`.
  The on-device test harness folder renamed to `kmep_harness/` too.

## 0.1.0 — Internal prototype

Original state as validated against live traffic; see
`docs/AGENT_HANDOFF.md` for the full evidence trail (success-rate
methodology, on-device PO token proof, remaining risks).
