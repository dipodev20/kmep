# Vidora / kmep-proto — стартовый каркас

**Статус: внутренний прототип Vidora** ("kmep-proto", в UI — «Vidora Extractor
(Beta)»). Это НЕ публичный KMEP — тот будет отдельным проектом на Kotlin
Multiplatform (`com.vidora.kmep`), когда этот прототип докажет архитектуру
на реальном трафике.

**Если ты агент, продолжающий эту работу — читай `docs/AGENT_HANDOFF.md`
ПЕРВЫМ, там весь актуальный контекст и следующий шаг.**

## Структура

```
vidora_kmep/
├── dart/
│   ├── lib/
│   │   ├── kmep.dart
│   │   └── src/
│   │       ├── models/kmep_models.dart
│   │       ├── clients/            # InnerTubeClient + 4 конфига
│   │       ├── parsers/player_parser.dart
│   │       ├── resolvers/stream_resolver.dart  # активная работа
│   │       └── core/               # Orchestrator, RemoteConfig, Cache
│   ├── test/player_parser_test.dart
│   ├── tool/                       # диагностика
│   │   ├── verify_prod_pipeline.js # ГЛАВНАЯ ПРОВЕРКА: прод-константы против живого YouTube
│   │   ├── probe_nsig_pipeline.js  # полный прогон sig/nsig + Range-запрос (ожидание: HTTP 206)
│   │   ├── solve_with_ytdlp.js     # эталонная сверка с ejs-солвером yt-dlp
│   │   ├── fetch_challenge.js      # общий модуль: свежий challenge из WEB playerResponse
│   │   ├── find_nsig.js            # брутфорс-перебор кандидатов (историческое, см. handoff)
│   │   ├── player_js_probe.dart    # качает player.js в player_js_dump.js
│   │   ├── extract_function.js     # извлечение тела функции по имени
│   │   ├── test_harness.js         # смок-тест шима
│   │   └── browser_shim.js         # заглушки под браузерные API
│   └── pubspec.yaml                # чистый Dart-пакет, БЕЗ Flutter
├── flutter_integration/flutter_js_runtime.dart  # требует Flutter SDK
├── backend/                        # Python fallback (yt-dlp)
└── docs/
    ├── IDEAS.md
    └── AGENT_HANDOFF.md            # контекст для продолжения работы
```

## Быстрый старт

```
cd dart
dart pub get
dart run tool/e2e_orchestrator.dart            # живой прогон через полный оркестратор
dart run tool/e2e_orchestrator.dart --pot-http # то же + PO-токены (нужен сервер bgutil)
node tool/verify_prod_pipeline.js dQw4w9WgXcQ  # проверка прод-констант резолвера
```

Метрики success rate (50 видео из поиска): `dart run tool/metrics_batch.dart 50 [--pot-http]`.
Подъём POT-сервера и прочее — в `docs/AGENT_HANDOFF.md`.

Статус прототипа: **success rate 98% (49/50) на выборке с POT** — критерий
переноса в KMP (≥95%) достигнут на данной инфраструктуре.
