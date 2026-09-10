# Awesome-list PR kit

Готовые материалы для подачи KMEP в awesome-списки. Всё проверено по
живым репозиториям (структура разделов, правила, алфавитный порядок)
на 2026-09-10. Комментарии для владельца — по-русски, PR-тексты —
по-английски (язык целевых репо).

Порядок подачи по убыванию ценности:

1. **awesome-dart** — целевая аудитория, лёгкий приём.
2. **awesome-flutter** — огромный трафик, строгий мейнтейнер.
3. **alternative-front-ends** (9.1k⭐) — аудитория NewPipe/LibreTube,
   идеальное место для «alternative to NewPipeExtractor».
4. **digitalblossom/alternative-frontends** (2.3k⭐) — та же
   аудитория, меньший список.
5. ~~awesome-youtube~~ — **репозиторий не существует** (404,
   проверено через GitHub API). Не тратить время; ближайшие живые
   аналоги — два списка выше.

`gh` CLI в этой среде не авторизован для PR в чужие репо — команды для
ручного выполнения в конце каждой секции.

---

## 1. awesome-dart (github.com/yissachar/awesome-dart)

Правила (CONTRIBUTING): одна запись, формат `- [Name](url) - Description.`
без эмодзи и без ⭐-подсчёта руками. Раздел **Utilities**, списочный
порядок — не строгий алфавит, но близок к нему; место — по алфавиту
между `built_value` и `Frappe`… фактически после `Darq`/`Basics`
(конец списка).

### Diff (README.md, раздел `## Utilities`, в конец списка)

```diff
 ## Utilities

 * [Archive](https://pub.dartlang.org/packages/archive) - A library to encode and decode various archive and compression formats.
 * [built_collection](https://github.com/google/built_collection.dart) - Immutable collections via the builder pattern. 
 * [built_value](https://github.com/google/built_value.dart) - Immutable value types, enum classes, and serialization.
 * [Frappe](https://pub.dartlang.org/packages/frappe) - A functional reactive programming library for Dart. Frappé extends the functionality of Dart's streams, and introduces new concepts like properties/signals.
 * [Quiver](https://github.com/google/quiver-dart) - A set of utility libraries that makes using many libraries easier and more convenient, or adds additional functionality.
 * [route_hierarchical](https://github.com/angular/route.dart) - Route is a client routing library for Dart that helps make building single-page web apps.
 * [Darq](https://pub.dev/packages/darq) - A port of functional LINQ from the .NET library.
 * [Basics](https://github.com/google/dart-basics) -  A Dart library containing convenient extension methods on basic Dart objects.
+* [kmep](https://github.com/dipodev20/kmep) - A YouTube extraction library running fully in-process: multi-client InnerTube fallback, on-device player.js execution and BotGuard PO token generation, with search, shorts, channels, playlists and comments behind a typed facade. No JVM, no Python, no server.
```

### PR title

```
Add kmep — YouTube extraction library (on-device PO tokens, no JVM/Python)
```

### PR body

```markdown
Adds [kmep](https://github.com/dipodev20/kmep) to Utilities.

kmep is a from-scratch YouTube extraction library for pure Dart/Flutter:
multi-client InnerTube fallback (ANDROID_VR → WEB → IOS → WEB_SAFARI → TV,
runtime-tunable via remote config), real `player.js` execution for
signature/n resolution, and on-device BotGuard PO token generation —
no backend server, no JVM, no Python runtime. Typed API covering videos
(up to 4K, live/HLS), search, shorts, channels, playlists and comments.

Production-tested as the extraction engine of a daily-driver Android app:
98% success rate (49/50 live-audited). GPL-3.0-or-later, pre-1.0.

The entry follows the list format (one line, no emoji/star counts).
```

### Ручные команды (fork → branch → commit → PR)

```bash
gh repo fork yissachar/awesome-dart --clone
cd awesome-dart
git checkout -b add-kmep
# применить diff выше в README.md
git commit -am "Add kmep — YouTube extraction library"
git push -u origin add-kmep
gh pr create --repo yissachar/awesome-dart \
  --title "Add kmep — YouTube extraction library (on-device PO tokens, no JVM/Python)" \
  --body-file kmep_pr_body.md
```

---

## 2. awesome-flutter (github.com/Solido/awesome-flutter)

Правила: запись с `⭐`-счётчиком, автором (`by ...`), раздел
**Utilities** (строки с `[N⭐]`). Формат: `- [Name](url) [N⭐] - Description by [Author](gh-url).`
Обновлять ⭐-число на момент подачи (взять со страницы репо).

### Diff (README.md, раздел `## Utilities`, по алфавиту: после `Melos`, в конец перед `### VSCode`)

```diff
 - [Melos](https://github.com/invertase/melos) [1382⭐] - Manage projects with multiple packages, automated versioning, changelogs & publishing via Conventional Commits by [Invertase](https://github.com/invertase).
+- [KMEP](https://github.com/dipodev20/kmep) [N⭐] - YouTube extraction in pure Dart: streams up to 4K, search, shorts, channels, playlists, comments; on-device player.js + BotGuard PO tokens, no backend server by [dipodev20](https://github.com/dipodev20).

### VSCode
```

(заменить `N⭐` на актуальное число звёзд KMEP перед подачей)

### PR title

```
Add KMEP to Utilities
```

### PR body

```markdown
Adds [KMEP](https://github.com/dipodev20/kmep) to Utilities.

KMEP is a YouTube extraction library in pure Dart for Flutter apps:
video streams up to 4K (live/HLS), typed search, shorts feed, channels,
playlists and comments — all via InnerTube, with no JVM, Python runtime
or backend server. It runs YouTube's real `player.js` for signature
resolution and generates BotGuard PO tokens on-device (the only such
Dart implementation I'm aware of).

Production-tested as the default engine of a daily-driver Android app
(98% success rate, 49/50 live-audited). GPL-3.0-or-later, pre-1.0.

Follows the list's entry format; star count is as of today.
```

### Ручные команды

```bash
gh repo fork Solido/awesome-flutter --clone
cd awesome-flutter
git checkout -b add-kmep
# применить diff (обновить N⭐) в README.md
git commit -am "Add KMEP to Utilities"
git push -u origin add-kmep
gh pr create --repo Solido/awesome-flutter \
  --title "Add KMEP to Utilities" --body-file kmep_pr_body.md
```

---

## 3. alternative-front-ends (github.com/mendel5/alternative-front-ends, 9.1k⭐)

Список фронтендов/альтернатив; YouTube-секция — строки формата
`- [Name](url): Description`. Это место, где KMEP видит своя
аудитория (NewPipe/LibreTube-подобные проекты). KMEP — не фронтенд,
а движок — подавать как **related tooling** в конец YouTube-секции
(в списке уже есть не-фронтенды, например instance-списки).

### Diff (README.md, YouTube-секция, в конец блока YouTube-фронтендов)

```diff
 - [LibreTube](https://github.com/libre-tube/LibreTube): Android frontend for YouTube, based on Piped
+- [KMEP](https://github.com/dipodev20/kmep): Not a frontend but the engine for building one — a pure-Dart YouTube extraction library (alternative to NewPipeExtractor) with on-device player.js execution and BotGuard PO token generation; used in production by a daily-driver Android app
```

### PR title

```
Add KMEP — Dart YouTube extraction library (engine for custom frontends)
```

### PR body

```markdown
Adds [KMEP](https://github.com/dipodev20/kmep) to the YouTube section —
flagging clearly that it's a library, not a frontend: it's the piece
you'd build a NewPipe/LibreTube-style app with, in pure Dart/Flutter.

Why it fits this list's audience: it generates BotGuard PO tokens
on-device (no bgutil server), runs YouTube's real `player.js` for
signature resolution, and falls back across five InnerTube clients
(ANDROID_VR → WEB → IOS → WEB_SAFARI → TV) with runtime-tunable
priority. 98% live-audited success rate in a month of production use.
GPL-3.0-or-later, pre-1.0.

Happy to move/drop the entry if maintainers feel a library doesn't
belong here — but several frontends in the list already reference
their extraction engines, so this seemed useful context for readers
choosing what to build on.
```

### Ручные команды

```bash
gh repo fork mendel5/alternative-front-ends --clone
cd alternative-front-ends
git checkout -b add-kmep
# применить diff в README.md (секция YouTube)
git commit -am "Add KMEP — Dart YouTube extraction library"
git push -u origin add-kmep
gh pr create --repo mendel5/alternative-front-ends \
  --title "Add KMEP — Dart YouTube extraction library (engine for custom frontends)" \
  --body-file kmep_pr_body.md
```

---

## 4. digitalblossom/alternative-frontends (2.3k⭐)

Формат: подпункты под заголовком фронта, `   - Description.`
Точечное место — в `### YouTube` как отдельный пункт-инструмент.

### Diff (README.md, `### YouTube`, в конец секции перед `### YouTube Music`)

```diff
 ### YouTube
 ...
+   - **[KMEP](https://github.com/dipodev20/kmep)** - Not a frontend but a library: pure-Dart YouTube extraction engine (multi-client InnerTube fallback, on-device player.js + BotGuard PO tokens) for building your own NewPipe-style app in Flutter.
```

### PR title

```
Add KMEP (Dart extraction library) to YouTube tools
```

### PR body

```markdown
Adds [KMEP](https://github.com/dipodev20/kmep) to the YouTube section.
It's a library rather than a frontend — the extraction engine you'd
build a YouTube frontend on, in pure Dart/Flutter: multi-client
InnerTube fallback, on-device player.js execution, on-device BotGuard
PO tokens (no server). GPL-3.0-or-later, production-tested (98%
live-audited success rate). Entry follows the section's format; happy
to adjust placement.
```

### Ручные команды

```bash
gh repo fork digitalblossom/alternative-frontends --clone
cd alternative-frontends
git checkout -b add-kmep
# применить diff в README.md (### YouTube)
git commit -am "Add KMEP (Dart extraction library) to YouTube tools"
git push -u origin add-kmep
gh pr create --repo digitalblossom/alternative-frontends \
  --title "Add KMEP (Dart extraction library) to YouTube tools" \
  --body-file kmep_pr_body.md
```

---

## Примечания

- **awesome-selfhosted**: пропущен сознательно — KMEP библиотека,
  а не self-hosted-сервис; критерий фильтрации там именно сервис.
- **sindresorhus/awesome**: принимает только сами awesome-списки,
  отдельные проекты — нет.
- ⭐-счётчики в awesome-flutter обновлять в день подачи.
- После мержа каждого PR — обновить README KMEP секцией
  "Featured in" (для соц-доказательства).
