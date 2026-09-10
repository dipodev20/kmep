# Changelog

All notable changes to KMEP are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
(pre-1.0: minor versions may carry breaking changes, noted below).

## [Unreleased]

- pub.dev publishing is planned once the API settles (issue tracked in
  README "Status").
- Multi-site support is explicitly out of scope for the 1.0 horizon.

## [0.3.0] — 2026-09-10

The three big "not yet" items from 0.2.0 are done: channels, playlists,
comments. All of them ride the unauthenticated InnerTube WEB client
(same as search — no JS runtime, no PO token, no player.js), so they
work on every platform KMEP runs on, including plain Dart servers.

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
- Live-response fixtures (`dart/test/fixtures/`) and 6 new unit
  tests — 53 total, all green.
- `dart/example/example.dart` now demonstrates the full surface
  end-to-end.
- `dart/tool/bench_kmep.dart` — reproducible live benchmark (cold
  bootstrap vs cached extraction), with a matching yt-dlp comparison
  command documented alongside.
- `llms.txt` — machine-readable project summary for AI assistants
  and crawlers.

### Changed

- **Package renamed: `kmep_proto` → `kmep`** (see Breaking changes
  below); repository renamed to `dipodev20/kmep`; the on-device test
  harness moved to `kmep_harness/` (incl. Android namespace).
- **License switched from MIT to GPL-3.0-or-later**, the same license
  as NewPipe: this project is weeks of reverse-engineering work
  (on-device BotGuard, multi-client InnerTube fallback, real
  `player.js` execution) and copyleft keeps derivatives open.
  Taking this code, renaming it and shipping it closed-source is a
  copyright violation.

### Breaking changes

- Package renamed `kmep_proto` → `kmep`: update the dependency name in
  `pubspec.yaml` and imports to `package:kmep/kmep.dart`.
- `SearchResultPage.results` is now `List<VideoSearchResult>`
  (was `List<dynamic>` in 0.1.0).

### Fixed

- (none beyond the above in 0.3.0)

## [0.2.0] — 2026-09-09

Turned the internal prototype into something meant to be depended on
from outside Vidora. No extraction logic changed — the InnerTube
clients, `player.js` execution, and BotGuard PO token flow are
untouched and keep the ~98% success rate validated in production.
What changed is the *shape* of the library.

### Added

- **`Kmep` facade** (`lib/src/kmep_client.dart`) — one class to
  construct instead of wiring `ExtractionOrchestrator` +
  `StreamResolver` + `CachedWatchPageMetaProvider` +
  `BotGuardJsPoTokenProvider` by hand. `Kmep.withOnDevicePoToken(...)`
  is the one-call setup for the common case.
- **Search and shorts feed promoted into the library**
  (`lib/src/search/search_client.dart`), typed as
  `VideoSearchResult` / `SearchResultPage` / `ShortsFeedPage`.
  This logic previously lived duplicated in the Vidora app's glue
  code; it's YouTube-extraction logic, so it belongs here.
- **`CachedWatchPageMetaProvider`** — TTL-caching decorator for
  `WatchPageMetaProvider` so the watch page is fetched once per video
  across orchestrator and PO token binding.
- **`BotGuardJsPoTokenProvider.bindingFor`** — async alternative to
  the synchronous `bindingResolver`, for bindings that come from the
  network (e.g. `visitorData` from the watch page).
- Curated public export surface in `lib/kmep.dart`, grouped by
  purpose with doc comments.
- Unit tests for the promoted search parser and the cache decorator;
  Dart CI workflow (`.github/workflows/dart_ci.yml`).
- Project branding (logo, cover) in `branding/`.

### Changed

- `SearchResultPage.results` is now typed (see Breaking changes).

## [0.1.0] — 2026-08-22

Initial internal prototype ("kmep-proto") for the Vidora app — proof
of the architecture on real traffic before any public API existed.
Shipped with the on-device test harness (APK) and the full evidence
trail in `docs/AGENT_HANDOFF.md`: visitor-data parity with yt-dlp,
the VISIONOS client addition, live-verified extraction matrix, and
the on-device BotGuard PO token proof (R1/R2/R3 experiments).

### Added

- InnerTube multi-client fallback (`ANDROID_VR`/`WEB`/`IOS`/
  `WEB_SAFARI`/`TV`), client configs calibrated against live traffic.
- `StreamResolver`: signature/`n` reversal via real `player.js`
  execution in a pluggable `JsRuntime` (Node process runtime included;
  WebView runtime in the Flutter integration package).
- `BotGuardJsPoTokenProvider`: on-device BotGuard PO token generation
  — no bgutil server.
- `ExtractionOrchestrator` with fallback order, circuit-breaker-style
  `RemoteConfig`, cache manager, watch-page metadata provider.
- `NodeProcessJsRuntime`, diagnostic tools (`dart/tool/`), harness
  APK project, Python emergency-fallback backend prototype
  (`backend/`, unused by the library).

[Unreleased]: https://github.com/dipodev20/kmep/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/dipodev20/kmep/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/dipodev20/kmep/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/dipodev20/kmep/releases/tag/v0.1.0
