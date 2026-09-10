# KMEP Flutter integration — WebViewJsRuntime

[![Dart CI](https://github.com/dipodev20/kmep/actions/workflows/dart_ci.yml/badge.svg)](https://github.com/dipodev20/kmep/actions/workflows/dart_ci.yml)
[![License: GPLv3](https://img.shields.io/badge/license-GPLv3-0078D7)](../LICENSE)

The Flutter piece of [KMEP](../README.md) — a YouTube extraction
library for Dart and a stable alternative to NewPipeExtractor. This
package provides the production-tested `JsRuntime` implementation that
lets KMEP run YouTube's `player.js` and BotGuard inside a Flutter app
on Android and iOS, fully on-device.

## Why a separate package

The core `kmep` package is pure Dart (runs and tests on any machine
with just the Dart SDK). A JS engine, however, is inherently
platform-specific — so it lives here, where Flutter SDK and the
WebView plugin can be pulled in without polluting the library.

## Quick start

```yaml
# pubspec.yaml of your Flutter app
dependencies:
  kmep:
    git:
      url: https://github.com/dipodev20/kmep
      path: dart
  kmep_flutter_integration:
    path: ../flutter_integration   # or a git dependency
```

```dart
import 'package:kmep/kmep.dart';
import 'package:kmep_flutter_integration/webview_js_runtime.dart';

final kmep = Kmep.withOnDevicePoToken(
  jsRuntime: WebViewJsRuntime(),       // executes player.js
  potJsRuntime: WebViewJsRuntime(),    // separate JS context for BotGuard
  fetchText: (url) => http.get(Uri.parse(url)).then((r) => r.body),
);

final video = await kmep.getVideo('dQw4w9WgXcQ');
```

## Two runtimes, one recommendation

| Runtime | Status | Use it when |
|---|---|---|
| **`WebViewJsRuntime`** (this one) | ✅ production-tested in [Vidora](https://github.com/dipodev20) | always on Flutter — this is the default choice |
| `FlutterJsRuntime` (QuickJS) | ⚠️ legacy/reserve | never for `player.js`: the QuickJS fork crashes on it non-deterministically ("unconsistent stack size"); kept only as a reference |

The WebView runtime drives a headless `flutter_inappwebview` with the
system engine (Chromium on Android, WebKit on iOS) — the same JS
engine a real browser uses, which is exactly what `player.js` and
BotGuard expect.

## Notes for Flutter developers

- **Two separate instances** for `jsRuntime` and `potJsRuntime` —
  running player.js and BotGuard in the same JS globals caused
  cross-contamination during testing. The constructor is cheap.
- **Android**: needs nothing special — headless WebView works without
  a visible UI. Internet permission as usual.
- **Dispose**: call `dispose()` on runtimes your app no longer needs
  (a `dispose`d runtime rejects further calls loudly).
- **Threading**: runtimes are single-instance; KMEP serializes access
  internally, so you can share one `Kmep` across your app.

## Tests

```bash
flutter pub get
flutter test    # 14 tests over both runtimes' plumbing
```

## License

GPL-3.0-or-later — see [../LICENSE](../LICENSE).
