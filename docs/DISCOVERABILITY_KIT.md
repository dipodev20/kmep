# Discoverability kit — PR texts & registry entries

Готовые к копипасту материалы для внешних площадок. English — так
принято в awesome-списках; комментарии по-русски для владельца.

---

## 1. awesome-flutter (github.com/sindresorhus/awesome-flutter)

Правила репо: PR должен добавлять ОДНУ строку в правильный раздел,
без описаний в списке. Раздел "Utilities" ближе всего (библиотека-
инструмент, не UI). Строку держать алфавитного порядка.

**PR Title:** `Add kmep to Utilities`

**PR Body:**

```markdown
Adds [KMEP](https://github.com/dipodev20/kmep) — a YouTube extraction
library in pure Dart: videos up to 4K, search, shorts, channels,
playlists, comments. On-device player.js execution and on-device
BotGuard PO token generation (no backend server). Production-tested
as the extraction engine of a daily-driver Android app (98% success
rate, 49/50 live-audited). GPL-3.0-or-later.
```

**Diff** (в `README.md`, раздел `## Utilities`, по алфавиту):

```diff
 ## Utilities
 ...
+- [KMEP](https://github.com/dipodev20/kmep) - YouTube extraction in pure Dart: streams up to 4K, search, shorts, channels, playlists, comments; on-device player.js + PO tokens, no server. GPL-3.0-or-later by [dipodev20](https://github.com/dipodev20)
```

---

## 2. awesome-dart (github.com/yissachar/awesome-dart)

**PR Title:** `Add kmep — YouTube extraction library (on-device PO tokens, no JVM)`

**PR Body:**

```markdown
Adds [KMEP](https://github.com/dipodev20/kmep) to Utilities — a
from-scratch YouTube extraction library for pure Dart/Flutter:
multi-client InnerTube fallback (ANDROID_VR → WEB → IOS → TV,
runtime-tunable via remote config), real `player.js` execution for
signature/n resolution, and on-device BotGuard PO token generation
with zero external servers. Typed API covering videos (up to 4K,
live/HLS), search, shorts, channels, playlists and comments.
Production-tested (98% success rate over a month of daily use).
GPL-3.0-or-later.
```

**Diff** (в `README.md`, раздел Utilities, по алфавиту):

```diff
 ## Utilities
 ...
+- [kmep](https://github.com/dipodev20/kmep) - YouTube extraction in pure Dart: multi-client InnerTube fallback, on-device player.js + BotGuard PO tokens, search/channels/playlists/comments.
```

---

## 3. awesome-youtube (github.com mkear?/awesome-youtube — проверять актуальный
   мейнтейнера при открытии PR)

**PR Title:** `Add KMEP — Dart YouTube extractor (on-device PO tokens)`

**PR Body:**

```markdown
Adds [KMEP](https://github.com/dipodev20/kmep) under Extractors /
Libraries — a pure-Dart alternative to NewPipeExtractor: same InnerTube
multi-client approach (ANDROID_VR/WEB/IOS/TV), but running entirely
in-process in Flutter/Dart apps with no JVM and no Python runtime.
Notably, it generates BotGuard PO tokens on-device (no bgutil server).
Covers video streams up to 4K, live/HLS, search, shorts, channels,
playlists and comments behind a typed facade. 98% live-audited success
rate from a month in production. GPL-3.0-or-later.
```

**Diff** (в `README.md`, раздел Extractors — найти секцию по факту,
строка по алфавиту):

```diff
 ## Extractors / Libraries
 ...
+- [KMEP](https://github.com/dipodev20/kmep) - pure-Dart YouTube extraction library (alternative to NewPipeExtractor): on-device player.js + BotGuard PO tokens, streams up to 4K, search/channels/playlists/comments.
```

---

## 4. awesome (sindresorhus/awesome) — лист "awesome" не принимает
   отдельные проекты, только сами списки. ПРОПУСТИТЬ. Вместо него:
   pub.dev (см. ниже, задача отдельная) и awesome-selfhosted.

## 5. awesome-selfhosted (github.com/awesome-selfhosted/awesome-selfhosted)

Применим **условно**: KMEP сам по себе не self-hosted-сервис, но
`backend/` (аварийный yt-dlp-фолбэк) — FastAPI-сервис, который можно
развернуть. Честнее НЕ подавать проект целиком (риск reject), а
подать после выноса бэкенда в отдельный репо, если захочется.

**Вердикт: отложить.** Текущая позиция проекта — библиотека, а не
сервис; awesome-selfhosted строго фильтрует по этому критерию.

---

## 6. FreeTube / LibreTube discussions (не PR, а посты)

Там, где просят "alternative engines", уместен комментарий:

```markdown
If anyone's looking for a Dart-side engine: KMEP
(https://github.com/dipodev20/kmep) is a pure-Dart YouTube extraction
library with the same multi-client InnerTube approach — notably it
generates BotGuard PO tokens on-device, no bgutil server needed. It's
GPLv3, pre-1.0, production-tested in a daily-driver Android app.
```

---

## 7. MCP-каталоги и реестры

### oss-recommender-mcp / reposcout — JSON-запись

```json
{
  "name": "kmep",
  "full_name": "dipodev20/kmep",
  "description": "YouTube extraction library in pure Dart — a stable alternative to NewPipeExtractor for Flutter apps. Multi-client InnerTube fallback (ANDROID_VR → WEB → IOS → WEB_SAFARI → TV), on-device player.js execution for signature/n resolution, on-device BotGuard PO token generation (no server, no JVM, no Python). Videos up to 4K, live/HLS, search, shorts, channels, playlists, comments behind a typed Kmep facade. Production-tested: 98% success rate (49/50 live-audited), 4-5 weeks as the default engine of a daily-driver Android app. Pre-1.0 (v0.3.0).",
  "tags": [
    "youtube", "youtube-extractor", "newpipe", "newpipe-alternative",
    "innertube", "po-token", "botguard", "player-js", "multi-client",
    "dart", "flutter", "flutter-library", "video-downloader",
    "yt-dlp-alternative", "freetube", "libretube", "open-source",
    "gplv3"
  ],
  "url": "https://github.com/dipodev20/kmep",
  "repository": "https://github.com/dipodev20/kmep",
  "language": "Dart",
  "license": "GPL-3.0-or-later",
  "keywords_query_hints": [
    "newpipe alternative", "newpipe extractor alternative",
    "youtube extractor dart", "youtube flutter library",
    "innertube dart", "po token on device", "yt-dlp dart binding",
    "freetube engine", "youtube no api"
  ]
}
```

Поле `keywords_query_hints` — нестандартное: если реестр строгий к
схеме, удалить его, остальное совпадает с типовыми полями
(name/description/tags/url/language).

### Прочие места регистрации (кратко)

| Где | Что подавать | Заметка |
|---|---|---|
| **pub.dev** | `dart publish` из `dart/` | сейчас `publish_to: none`; главная будущая точка входа для Dart-разработчиков. Перед публикацией: убрать path-only зависимости, заменить git-ссылку в README |
| **llmshub / awesome-mcp-servers** | не применимо: KMEP не MCP-сервер | если появится демо-MCP поверх KMEP (например, "search YouTube" tool) — тогда да, и это сильный ход для discoverability |
| **GitHub Topics** | уже сделано (20 topics) | см. задачу 1 |
| **Social preview** | только через web UI: Settings → Social preview → upload `branding/cover.png` | API-эндпоинт для этого отсутствует, руками через браузер |
| **OpenGraph/README** | уже сделано | `llms.txt` в корне — стандарт, который читают Crawlers ИИ (Claude/OpenAI уже индексируют) |

---

## Приоритет подачи

1. **awesome-dart** (наиболее релевантный аудиторий, лёгкий приём)
2. **awesome-flutter** (sindresorhus строг, но строка формата их правил)
3. **awesome-youtube** (нишевый, но целевой)
4. pub.dev — после стабилизации API (отдельная задача)
