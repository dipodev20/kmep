# Contributing to KMEP

Thanks for wanting to help. This document covers the practical bits:
setup, tests, code style, where things live, and how to pitch in
without reverse-engineering YouTube from scratch.

## The one document to read first

**[docs/AGENT_HANDOFF.md](docs/AGENT_HANDOFF.md)** is the project's
brain. It contains the full evidence trail — how the 98% success rate
was measured, how the on-device PO token was proven, which clients are
fragile and why, and what's already been tried and failed. Any PR
that touches extraction logic should be consistent with what's
documented there, and any new finding should end up there.

This applies double to AI agents working on this repo: AGENT_HANDOFF
is your context. Skim the table of contents before editing anything
in `dart/lib/src/`.

## Repository layout

```
dart/                  the library (pure Dart package)
  lib/kmep.dart        public export barrel — start here
  lib/src/clients/     InnerTube client + per-client configs (the matrix)
  lib/src/core/        orchestrator, PO tokens, cache, remote config
  lib/src/resolvers/   player.js signature/n resolution
  lib/src/search/      search + shorts feed
  lib/src/channel/     channels + playlists
  lib/src/comments/    comments + thread replies
  lib/src/runtimes/    NodeProcessJsRuntime (server/CLI JS engine)
  test/                unit tests (53) + live-response fixtures
  tool/                live diagnostics & benchmarks (not public API)
  example/             runnable end-to-end example
flutter_integration/  WebViewJsRuntime for Flutter apps (+ tests)
kmep_harness/         on-device smoke-test APK
backend/              optional emergency yt-dlp fallback (unused by the lib)
docs/                  AGENT_HANDOFF.md (evidence trail), IDEAS.md
```

## Setup

```bash
git clone https://github.com/dipodev20/kmep
cd kmep/dart
dart pub get
dart analyze   # must report "No issues found!"
dart test      # 53 tests, must all pass
```

Flutter-side pieces:

```bash
cd ../flutter_integration && flutter pub get && flutter test
```

## Before you open a PR

1. `dart analyze` — zero issues (warnings included; the repo is kept lint-clean).
2. `dart test` — all green.
3. `dart format lib test example tool` — formatting is `dart format`
   defaults, enforced by CI.
4. New public API needs a doc comment explaining **when** to use it,
   not just **what** it is. New extraction logic needs a unit test
   against a recorded live fixture (see `test/fixtures/` — dump a real
   response, trim it to the minimum, assert the parsed output).

## How to add a new InnerTube client

Clients live in `dart/lib/src/clients/client_configs.dart` as
`InnerTubeClientConfig` constants. To add one:

1. Capture the client's context block, headers, version and UA from
   a real client (yt-dlp's client research is the best public source;
   `dart/tool/client_matrix*.js` shows the calibration harness).
2. Add the config constant with honest flags:
   `requiresPoToken`, `needsSignatureTimestamp`, `needsVisitorData`,
   `supportsSabrOnly`, `maxQuality`, `noApiKey`.
3. Add it to `ClientRegistry.all` **in the position the fallback
   order should try it** — order is behavior, measure before guessing.
4. Extend the orchestrator tests to cover the new client's shape.
5. Document what it's good at (and what breaks it) in a comment on
   the constant — the next maintainer will thank you.

Keep client versions overridable via `RemoteConfig` — never hardcode
an assumption you wouldn't be able to fix over the air.

## Adding parsers (search renderers, comment shapes, …)

YouTube A/B-tests renderer shapes, so parsers must be resilient:

- Walk responses generically (see `_walk` in `channel_client.dart`)
  rather than hardcoding paths.
- Support both the current shape and the previous one when they
  differ materially (see `comment_parser.dart` for the pattern:
  `commentViewModel` + legacy `commentRenderer` fallback).
- Pin behavior with a fixture test from a real recorded response.

## Reporting bugs

Open a GitHub issue with:

- What you called (method + arguments), what you expected, what you got.
- `Kmep.lastPoTokenError` output if PO tokens are involved — it's the
  built-in diagnostic.
- Your platform (Flutter/CLI), `JsRuntime` implementation, and
  whether the video works on the same network in yt-dlp or NewPipe —
  that distinguishes "our bug" from "YouTube IP reputation".

Security-relevant findings (anything that would let you bypass rate
limits or leak user data): please open an issue without the
reproduction details first and we'll coordinate.

## Code style

- `dart format` defaults; no custom lint config beyond
  `lints/recommended` + a couple of documented suppressions.
- Comments explain **why**, not what. The repo mixes English (public
  API, docs) and Russian (internal experiment notes) — new public
  surface is English.
- No comments narrating the obvious; the GPL header (see any file)
  goes on every source file — copy it when creating one.

## AI agents

This repo is co-developed with AI agents and that's worked well —
with three rules:

1. Read `docs/AGENT_HANDOFF.md` before touching extraction logic.
   It encodes months of live-traffic findings you cannot rediscover
   from the code alone.
2. Don't refactor the extraction core (`core/`, `clients/`,
   `resolvers/`, `parsers/`) to make it "cleaner" — its shape is
   load-bearing. Public-API polish (facade, docs, tests) is fair game.
3. Verify live: `dart run tool/e2e_new.dart` and
   `dart run example/example.dart` hit real YouTube from your machine.
   If your network is bot-gated, say so in the PR instead of skipping.

## License

By contributing you agree your contributions are licensed under
GPL-3.0-or-later, same as the rest of the project.
