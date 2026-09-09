<p align="center">
  <img src="branding/cover.png" width="640" alt="KMEP — YouTube extraction for Dart" />
</p>

# KMEP

<p align="center">
  <a href="https://github.com/dipodev20/vidora-kmep-proto/actions/workflows/dart_ci.yml">
    <img src="https://github.com/dipodev20/vidora-kmep-proto/actions/workflows/dart_ci.yml/badge.svg" alt="Dart CI" />
  </a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPLv3-blue.svg" alt="License: GPLv3" /></a>
  <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/version-0.3.0-orange.svg" alt="Version 0.3.0" /></a>
  <a href="https://www.dart.dev"><img src="https://img.shields.io/badge/platform-Dart%20%7C%20Flutter-0175C2.svg" alt="Platform: Dart / Flutter" /></a>
</p>

A from-scratch YouTube extraction library for Dart — the multi-client
InnerTube fallback, on-device `player.js` execution, and on-device PO
token generation that made [NewPipeExtractor][newpipe] and [yt-dlp][ytdlp]
possible, packaged as a small dependency instead of a fork of an app.

[newpipe]: https://github.com/TeamNewPipe/NewPipeExtractor
[ytdlp]: https://github.com/yt-dlp/yt-dlp

```dart
final kmep = Kmep.withOnDevicePoToken(
  jsRuntime: myPlayerJsRuntime,
  potJsRuntime: myBotGuardRuntime, // a *separate* JS context
  fetchText: (url) => http.get(Uri.parse(url)).then((r) => r.body),
);

final video = await kmep.getVideo('dQw4w9WgXcQ');
print('${video.title} — ${video.streams.length} streams');

final results = await kmep.search('lofi hip hop');
final channel = await kmep.getChannel('UC-lHJZR3Gqxm24_Vd_AJ5Yw');
final playlist = await kmep.getPlaylist('PLFgquLnL59aCl_2TQvOiD5Vgm1hCaGSI');
final comments = await kmep.getComments('dQw4w9WgXcQ');
```

## Status

This started as an internal validation prototype for the [Vidora][vidora]
app and is being opened up as a standalone, freely usable library. The
extraction pipeline itself has been running in production for 4–5 weeks
without a crash and holds a **98% success rate (49/50)** against a live
sample (see `docs/AGENT_HANDOFF.md` for methodology). What's new in this
pass is the public surface: a single `Kmep` facade, typed search/shorts
results instead of raw JSON maps, and curated exports — see
[CHANGELOG.md](CHANGELOG.md).

[vidora]: https://github.com/dipodev20

**Pre-1.0**: the API can still change between minor versions. Package name
is `kmep_proto` for now — it'll likely become just `kmep` once the API
settles; that rename is tracked, not done silently.

## What it does

| Feature | Status |
|---|---|
| Video metadata + resolved stream URLs | done |
| Multi-client fallback (`ANDROID_VR` -> `WEB` -> `IOS` -> `WEB_SAFARI` -> `TV`) | done |
| Signature / `n`-parameter resolution (real `player.js` execution) | done |
| On-device PO token generation (BotGuard, no external server) | done |
| Search | done |
| Shorts feed | done |
| Live streams / HLS | done (single muxed stream, as YouTube serves it) |
| Channels (header, tabs, videos with pagination) | done |
| Playlists (header, videos with pagination) | done |
| Comments (top/newest sort, pages, thread replies) | done |
| Channel shorts/live tabs | done (params exported, same `getChannelVideos` call) |
| Sites other than YouTube | out of scope for now (see below) |

## Why not just use NewPipeExtractor?

Different runtime, same idea. NewPipeExtractor is JVM (Kotlin/Java); this
is pure Dart, for apps that don't want a JVM dependency. It's a
complement, not a replacement — this library's own router falls back to
NewPipeExtractor on any failure in the app it was built for.

## Install

Not on pub.dev yet. Depend on it via git or path:

```yaml
dependencies:
  kmep_proto:
    git:
      url: https://github.com/dipodev20/vidora-kmep-proto
      path: dart
```

## Beyond videos: channels, playlists, comments

Everything below rides the same InnerTube WEB client — no JS runtime, no
PO token, fully paginated:

```dart
// Channels: header (name, handle, avatar, banner, subs, videos,
// description, links, tabs) and the Videos tab with pagination.
final channel = await kmep.getChannel('UC-lHJZR3Gqxm24_Vd_AJ5Yw');
final page = await kmep.getChannelVideos(channel.channelId);
// ... page.continuation -> next page; kChannelShortsTab /
// kChannelLiveTab params swap the tab (newest/popular/oldest sorts
// are exported too).

// Playlists: header + first page of videos (accepts a bare PL... id
// or a full watch URL).
final playlist = await kmep.getPlaylist('PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI');
final rest = await kmep.getPlaylistVideos(
    playlist.playlistId, playlist.continuation!);

// Comments: top/newest ordering, pagination, and thread replies
// (each thread carries its own repliesContinuation).
final comments = await kmep.getComments('dQw4w9WgXcQ');
final thread = comments.items.first; // pinned + hearted out of the box
final replies = await kmep.getCommentReplies(thread.repliesContinuation!);
```

## Platform integration

KMEP needs a `JsRuntime` — something that can execute a real `player.js`
(and, if you want on-device PO tokens, BotGuard's script). This is
deliberately not bundled, since the right implementation depends on your
platform:

- **Flutter**: use `WebViewJsRuntime` from [`flutter_integration/`](flutter_integration)
  in this repo (built on `webview_flutter`). This is the one actually
  used in production — a `flutter_js`/QuickJS-based runtime was tried
  first and doesn't reliably execute `player.js`.
- **Server / CLI**: `NodeProcessJsRuntime` (in `dart/lib/src/runtimes/`)
  shells out to a local `node` binary.
- **Anything else**: implement the `JsRuntime` interface yourself — it's
  two methods (`bootstrap`, `call`).

See `dart/lib/src/kmep_client.dart` doc comments and
`dart/example/example.dart` for the full wiring.

## Legal

This works against YouTube's undocumented internal API (InnerTube), the
same surface NewPipeExtractor and yt-dlp use. Using it may conflict with
YouTube's Terms of Service depending on how you use it and your
jurisdiction; that risk is on whoever deploys it, same as with any other
extraction library. This repository ships no YouTube content, credentials,
or API keys — only the client-side logic to talk to endpoints YouTube's
own apps already call.

## Contributing / continuing this work

If you're an agent or contributor picking this up: **read
`docs/AGENT_HANDOFF.md` first** — it has the full evidence trail (how the
success rate was measured, the on-device PO token proof, known risks) and
the actual next steps, which are more current than anything summarized
here.

## License

GPL-3.0-or-later — see [LICENSE](LICENSE). The same license as
NewPipe: you are free to use, study, modify and redistribute this
library, **but any redistributed or derivative work must stay open
under GPLv3 and credit this project** — closed-source rebranding of
this code is a license violation and will be treated as one.
