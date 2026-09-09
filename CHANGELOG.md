# Changelog

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
- No channel or playlist extraction — `ChannelInfo` exists as a model
  but nothing populates it yet.
- No comments support (`CommentInfo` is a placeholder model).
- YouTube only — there is no NewPipe-style `StreamingService`
  abstraction for other sites. Multi-site support would be a 1.0-scope
  change, not a patch on top of this API.
- Package is still named `kmep_proto` and depended on via a relative
  path from Vidora. Renaming/publishing is a deliberate separate step
  (see README "Status").

## 0.1.0 — Internal prototype

Original state as validated against live traffic; see
`docs/AGENT_HANDOFF.md` for the full evidence trail (success-rate
methodology, on-device PO token proof, remaining risks).
