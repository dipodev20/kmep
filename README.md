<p align="center">
  <img src="branding/cover.png" width="640" alt="KMEP — YouTube extraction for Dart" />
</p>

<p align="center">
  <a href="https://github.com/dipodev20/kmep/actions/workflows/dart_ci.yml">
    <img src="https://github.com/dipodev20/kmep/actions/workflows/dart_ci.yml/badge.svg" alt="Dart CI" />
  </a>
</p>

<p align="center">
  <a href="https://git.io/Jv05X"><img src="https://img.shields.io/badge/license-GPLv3-0078D7?style=for-the-badge&logo=gnu" alt="License: GPLv3" /></a>
  <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/version-0.3.0-FF4F00?style=for-the-badge&logo=git&logoColor=white" alt="Version 0.3.0" /></a>
  <a href="https://www.dart.dev"><img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" /></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" /></a>
  <a href="https://nodejs.org"><img src="https://img.shields.io/badge/Node.js-339933?style=for-the-badge&logo=nodedotjs&logoColor=white" alt="Node.js" /></a>
  <a href="https://www.youtube.com"><img src="https://img.shields.io/badge/InnerTube-FF0000?style=for-the-badge&logo=youtube&logoColor=white" alt="YouTube InnerTube" /></a>
</p>

<p align="center">
  <a href="https://github.com/dipodev20/kmep">
    <img src="https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=18&duration=2800&pause=900&color=F7F7F7&center=true&vCenter=true&multiline=true&repeat=true&width=650&lines=%3Cvideo%2C+streams%3E+%3D+await+kmep.getVideo(id);%3Csearch%2C+shorts%3E+%3D+kmep.search(q)%2C+kmep.shortsFeed(q)%3B%3Cchannel%2C+playlist%3E+%3D+kmep.getChannel(uc)%2C+kmep.getPlaylist(pl)%3B%3Ccomments%2C+replies%3E+%3D+kmep.getComments(id)%3B" alt="Typing SVG" />
  </a>
</p>

<br />

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

final video    = await kmep.getVideo('dQw4w9WgXcQ');
final results  = await kmep.search('lofi hip hop');
final channel  = await kmep.getChannel('UC-lHJZR3Gqxm24_Vd_AJ5Yw');
final playlist = await kmep.getPlaylist('PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI');
final comments = await kmep.getComments('dQw4w9WgXcQ');
```

<img src="https://raw.githubusercontent.com/dipodev20/kmep/main/branding/wave.svg" width="100%" alt="" />

## 📦 What it does

| | Feature | Status |
|---|---|---|
| 🎬 | Video metadata + resolved stream URLs (up to 4K) | ✅ done |
| 🛡️ | Multi-client fallback (`ANDROID_VR` → `WEB` → `IOS` → `WEB_SAFARI` → `TV`) | ✅ done |
| 🔏 | Signature / `n`-parameter resolution (real `player.js` execution) | ✅ done |
| 🤖 | On-device PO token generation (BotGuard, **no external server**) | ✅ done |
| 🔍 | Search | ✅ done |
| ⚡ | Shorts feed | ✅ done |
| 📡 | Live streams / HLS | ✅ done (single muxed stream, as YouTube serves it) |
| 📺 | Channels (header, tabs, videos with pagination) | ✅ done |
| 📃 | Playlists (header, videos with pagination) | ✅ done |
| 💬 | Comments (top/newest sort, pages, thread replies) | ✅ done |
| 🎞️ | Channel shorts/live tabs | ✅ done (params exported, same `getChannelVideos` call) |
| 🌍 | Sites other than YouTube | 🚧 out of scope for now |

<img src="https://raw.githubusercontent.com/dipodev20/kmep/main/branding/wave.svg" width="100%" alt="" />

## ⚡ Beyond videos: channels, playlists, comments

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

## 🧰 Built with

<p>
  <a href="https://dart.dev"><img src="https://skillicons.dev/icons?i=dart" alt="Dart" /></a>
  <a href="https://flutter.dev"><img src="https://skillicons.dev/icons?i=flutter" alt="Flutter" /></a>
  <a href="https://nodejs.org"><img src="https://skillicons.dev/icons?i=nodejs" alt="Node.js" /></a>
  <a href="https://git-scm.com"><img src="https://skillicons.dev/icons?i=git" alt="Git" /></a>
  <a href="https://github.com"><img src="https://skillicons.dev/icons?i=github" alt="GitHub" /></a>
  <a href="https://github.com/actions"><img src="https://skillicons.dev/icons?i=githubactions" alt="GitHub Actions" /></a>
</p>

## 📌 Status

This started as an internal validation prototype for the [Vidora][vidora]
app and is being opened up as a standalone, freely usable library. The
extraction pipeline itself has been running in production for 4–5 weeks
without a crash and holds a **98% success rate (49/50)** against a live
sample (see `docs/AGENT_HANDOFF.md` for methodology). What's new in this
pass is the public surface: a single `Kmep` facade, typed search/shorts
results instead of raw JSON maps, and curated exports — see
[CHANGELOG.md](CHANGELOG.md).

[vidora]: https://github.com/dipodev20

**Pre-1.0**: the API can still change between minor versions. The
package is named **`kmep`** (renamed from `kmep_proto` in 0.3.0) —
update your `pubspec.yaml` imports accordingly.

## 🚀 Install

Not on pub.dev yet. Depend on it via git or path:

```yaml
dependencies:
  kmep:
    git:
      url: https://github.com/dipodev20/kmep
      path: dart
```

## 🧩 Why not just use NewPipeExtractor?

Different runtime, same idea. NewPipeExtractor is JVM (Kotlin/Java); this
is pure Dart, for apps that don't want a JVM dependency. It's a
complement, not a replacement — this library's own router falls back to
NewPipeExtractor on any failure in the app it was built for.

## ⚔️ FAQ: "why not just use yt-dlp?"

yt-dlp is the de-facto industry standard and a magnificent one — its
client research directly informed KMEP's client matrix. But it solves a
different problem:

**"just bind it with ffigen/jnigen"** — yt-dlp is *Python*; ffigen binds
C and jnigen binds JVM, neither applies. Real-world options are shipping
a Python runtime with your app (≈80+ MB, separate process management) or
running it on a server (which is exactly what KMEP lets you avoid).

| | yt-dlp (CLI / server) | KMEP (in-process) |
|---|---|---|
| Runtime | Python interpreter | pure Dart, no embed |
| Cold start (process + one video) | ~11.8 s * | ~7 s incl. player.js bootstrap * |
| Warm extraction, same video | — (cache-less) | **0.00 s** (built-in cache) |
| Formats returned | depends on `-f` (4 with `best`) | all 27 (no format picker needed) |
| Live in a Flutter app | via server/process spawn | a Dart object |
| Zero-dependency on-device PO token | external bgutil server/WS | built-in (BotGuard, on-device) |
| Search/channels/playlists/comments API | CLI/JSON munging | typed Dart API |

\* Same device, same `android_vr` client, same IP, September 2026 —
see `tool/e2e_live_test.dart` and `docs/AGENT_HANDOFF.md` for
methodology. Both engines hit the same YouTube IP reputation limits;
neither is magically exempt from "Sign in to confirm you're not a bot".

**License note** — yt-dlp is [Unlicense](https://api.github.com/repos/yt-dlp/yt-dlp/license)
(public domain), so Ray De'Blois is right that it's maximally permissive.
KMEP chose GPLv3 for the same reason NewPipe did: this codebase is
weeks of reverse-engineering (on-device BotGuard, nsig discovery, client
matrix calibration), and copyleft keeps competitors from rebranding it
closed-source. If your project can't live with GPL-3.0-or-later, the
Unlicensed yt-dlp remains a great choice — they can even coexist:
KMEP's production router falls back to NewPipeExtractor.

**"where are the performance tests"** — fair. Live numbers are above
(same-IP, same-client, apples-to-apples); the methodology and the raw
runs are reproducible with the tools in this repo. Contributions with
benchmarks from other devices are welcome.

## 🗄️ What is `backend/` then?

A prototype **emergency fallback**, not a required component: a tiny
FastAPI service that shells out to yt-dlp *as a last resort* when every
on-device client fails (e.g. hostile IP reputation with no POT). It is
**optional, unused by the main library** (the Dart `Kmep` runs fully
on-device), disabled by not wiring `ExtractionOrchestrator.backendFallback`,
and kept here because it documented the survival path during the
prototype phase. The library itself does not import or require it —
it's one Python file you can delete without touching anything else.


## 🔌 Platform integration

KMEP needs a `JsRuntime` — something that can execute a real `player.js`
(and, if you want on-device PO tokens, BotGuard's script). This is
deliberately not bundled, since the right implementation depends on your
platform:

- **Flutter 📱**: use `WebViewJsRuntime` from [`flutter_integration/`](flutter_integration)
  in this repo (built on `webview_flutter`). This is the one actually
  used in production — a `flutter_js`/QuickJS-based runtime was tried
  first and doesn't reliably execute `player.js`.
- **Server / CLI 🖥️**: `NodeProcessJsRuntime` (in `dart/lib/src/runtimes/`)
  shells out to a local `node` binary.
- **Anything else 🔧**: implement the `JsRuntime` interface yourself — it's
  two methods (`bootstrap`, `call`).

See `dart/lib/src/kmep_client.dart` doc comments and
`dart/example/example.dart` for the full wiring.

## ⚖️ Legal

This works against YouTube's undocumented internal API (InnerTube), the
same surface NewPipeExtractor and yt-dlp use. Using it may conflict with
YouTube's Terms of Service depending on how you use it and your
jurisdiction; that risk is on whoever deploys it, same as with any other
extraction library. This repository ships no YouTube content, credentials,
or API keys — only the client-side logic to talk to endpoints YouTube's
own apps already call.

## 🐍 Contribution graph

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/dipodev20/kmep/output/github-contribution-grid-snake-dark.svg" />
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/dipodev20/kmep/output/github-contribution-grid-snake.svg" />
  <img alt="Contribution snake animation" src="https://raw.githubusercontent.com/dipodev20/kmep/output/github-contribution-grid-snake.svg" />
</picture>

## 🤝 Contributing / continuing this work

If you're an agent or contributor picking this up: **read
`docs/AGENT_HANDOFF.md` first** — it has the full evidence trail (how the
success rate was measured, the on-device PO token proof, known risks) and
the actual next steps, which are more current than anything summarized
here.

## 📄 License

<a href="LICENSE"><img src="https://img.shields.io/badge/license-GPLv3-0078D7?style=for-the-badge&logo=gnu" alt="GPLv3" align="right" /></a>

GPL-3.0-or-later — see [LICENSE](LICENSE). The same license as
NewPipe: you are free to use, study, modify and redistribute this
library, **but any redistributed or derivative work must stay open
under GPLv3 and credit this project** — closed-source rebranding of
this code is a license violation and will be treated as one.
