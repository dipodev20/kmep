# kmep

[![Dart CI](https://github.com/dipodev20/kmep/actions/workflows/dart_ci.yml/badge.svg)](https://github.com/dipodev20/kmep/actions/workflows/dart_ci.yml)
[![License: GPLv3](https://img.shields.io/badge/license-GPLv3-blue.svg)](../LICENSE)

Dart package for the KMEP YouTube extraction library. See the
[repository README](../README.md) for the full pitch, feature matrix,
and platform integration guide — this file is just the pub package
quick-reference.

## Quick start

```dart
import 'package:kmep/kmep.dart';

final kmep = Kmep.withOnDevicePoToken(
  jsRuntime: myPlayerJsRuntime,   // see ../flutter_integration or NodeProcessJsRuntime
  potJsRuntime: myBotGuardRuntime,
  fetchText: (url) => http.get(Uri.parse(url)).then((r) => r.body),
);

final video = await kmep.getVideo('dQw4w9WgXcQ');
final results = await kmep.search('lofi hip hop');
```

Runnable version: [`example/example.dart`](example/example.dart).

## Layout

```
lib/
├── kmep.dart              # public export barrel — start here
└── src/
    ├── kmep_client.dart   # the Kmep facade
    ├── models/            # VideoInfo, KMEPStream, VideoSearchResult, ...
    ├── search/            # search + shorts feed
    ├── channel/           # channels + playlists (browse endpoint)
    ├── comments/          # comments + thread replies (next endpoint)
    ├── clients/           # InnerTube client + per-client configs
    ├── parsers/           # player response parsing
    ├── resolvers/         # signature/n-parameter resolution (player.js)
    ├── runtimes/          # NodeProcessJsRuntime (server/CLI JsRuntime)
    └── core/              # orchestrator, PO tokens, cache, remote config
```

## Development

```
dart pub get
dart analyze
dart test
```

Diagnostic tools that hit live YouTube (not part of the public API,
useful when working on the extractor itself) are in `tool/` — see
`../docs/AGENT_HANDOFF.md`.
