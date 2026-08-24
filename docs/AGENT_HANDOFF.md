> **СТАТУС 2026-08-24, ночь (итог сессии «сделать KMEP рабочим»):**
> KMEP ВКЛЮЧЁН СКВОЗНОЙ ПУТЬ. 1) Vidora: ExtractorRouter — все точки
> вызова (плеер, шортсы, поиск, аудио/видео-скачивание) идут выбранным
> движком, любая ошибка беты -> тихий фолбэк на NewPipe; подпись в
> настройках обновлена. 2) Бета внутри использует on-device POT:
> BotGuardJsPoTokenProvider на ОТДЕЛЬНОМ WebBridgeJsRuntime (изоляция от
> player.js; ANDROID_VR-first токена не требует). 3) Десктопный e2e
> провайдера: tokenFor ~25 c холодно / из кэша мс, WEB без POT=SABR-only,
> с нашим POT прямой URL => InnerTube-слой принял токен как валидный.
> ВАЖНО (поправка к утренней формулировке): пронять «CDN принимает наш
> pot» этот прогон НЕ может — Range дал 206 и БЕЗ pot=, гейтинг на
> тестовом датацентровом IP в тот момент не активен, проверка не была
> различающей. R5 ФОРМАЛЬНО ОТКРЫТ: финальное подтверждение — стадия D
> харнеса на устройстве (гейтящийся мобильный IP), где пары «с pot=/без»
> дадут разницу. 4) Починен древний падёж
> test/widget_test (sqflite_ffi), flutter test 12 passed, analyze чист.
> APK: release build-84 (vidora-84.apk). CI-грабля: git push отсюда ловит
> "RPC failed; HTTP 408" на HTTP/2 — лечится `git -c http.version=HTTP/1.1
> push`. НЕ проверено на устройстве: реальный просмотр через бета-движок,
> тайминги POT в WebView (стадия D харнеса параллельной сессии), поведение
> при пересоздании Activity.

> **СТАТУС 2026-08-23, ночь:** kmep_proto ВНЕДРЁН в прод-приложение
> Vidora как «Vidora Extractor (Beta)» (репо ~/vidora, коммит 7914760).
> Архитектура: Kotlin VidoraExtractorBridge хостит СИСТЕМНЫЙ WebView
> (origin youtube.com) и релеит getStream/search/ping в Dart-сервис
> KmepExtractorService с полным ExtractionOrchestrator. flutter_inappwebview
> НЕ использован: несовместим с AGP 9.0.1 приложения (харнес это уже
> ловил). Комментарии — NOT_SUPPORTED (в kmep_proto их нет), маршрутизация
> движков — за отдельной сессией. Проверено локально: flutter analyze
> чист, 11 тестов маппинга passed; на устройстве ещё НЕ гонялось.
>
> **СТАТУС 2026-08-23, вечер (v15 прогон):** ЭТАП C ЗАКРЫТ — полный
> StreamResolver e2e на телефоне **PASS**. A/B/C все зелёные:
> A) ANDROID_VR 27 форматов 2160p; B) n-тест на ассете == эталон;
> C) реальный videoId -> watch-meta (STS=20683) -> WEB InnerTube OK ->
> player.js СКАЧАН ПО СЕТИ на устройство (2567494 байт — байт-в-байт тот
> же билд, что десктопу) -> бутстрап в свежем WebView ~2 c, fns=4090,
> fn="ji" -> resolve 27->1 (itag18 cipher) -> **HTTP 206**.
> Вывод: прод-пайплайн (InnerTube+Parser+StreamResolver) полностью
> рабочий на устройстве через WebViewJsRuntime; SABR-доминирование WEB —
> свойство клиента, не IP (телефон и датацентр дают одинаковые 26 SABR +
> itag18). Следующий шаг: перенос WebViewJsRuntime в прод-приложение
> Vidora (замена FlutterJsRuntime/QuickJS).
>
> **СТАТУС 2026-08-23, вечер (подготовка):** харнес v15 — этап C (полный
> StreamResolver e2e на устройстве) НАПИСАН и готов к прогону на телефоне.
> Логика этапа отрепетирована на десктопе (Node-рантайм): watch-meta ->
> WEB InnerTube -> player.js по сети -> прод-резолвер -> resolve -> Range:
> WEB отдал 27 форматов (26 SABR + itag18 cipher), resolve дал 1/1,
> HTTP 206 PASS. На устройстве ожидаем тот же поток через WebViewJsRuntime.
> APK v15: push в main -> артефакт `kmep-proto-harness-apk` (локальный
> пуш из среды агента невозможен — нет кредов).
>
> **СТАТУС 2026-08-23, день:** on-device smoke test ВЫПОЛНЕН ДО КОНЦА.
> Итог: **A-baseline PASS на телефоне** (ANDROID_VR, 27 форматов, 2160p,
> HTTP 200 — InnerTube+парсер полностью рабочие на устройстве).
> **Блокер найден и задокументирован**: форк QuickJS во flutter_js
> детерминированно падает на player.js ("InternalError: unconsistent
> stack size", всегда pc=2895) при определённых последовательностях
> evaluate — воспроизведён матрицей стадий (см. kmep_proto_harness,
> логи в истории чата владельца). Это баг ПЛАГИНА, не нашего кода.
> Пути решения JS-на-мобиле (по приоритету):
>   1. Собственный dart:ffi байндинг поверх prebuilt quickjs .so
>      (полный контроль стека/потока; работа на 1-2 дня);
>   2. Апстрим-иссью в abner/flutter_js с нашим репро-кейсом;
>   3. НЕ использовать JS на мобиле в MVP: ANDROID_VR-primary +
>      серверный фолбэк (backend/) там, где нужен WEB-клиент.
> APK харнеса v8 (воспроизведение): GitHub Actions артефакт.
> Ревью Claude — по материалам AGENT_HANDOFF целиком.
>
> ПАРАЛЛЕЛЬНО (отдельная ветка, код не тронут): завершено открытое
> исследование on-device POT/BotGuard без сервера bgutil — полный цикл
> воспроизведён, токен проходит валидацию GenerateIT. См. раздел
> «ОТДЕЛЬНОЕ ИССЛЕДОВАНИЕ: on-device POT/BotGuard» ниже + план интеграции.

Ты продолжаешь работу над `kmep-proto` — внутренним прототипом для Vidora
(отдельно от публичного будущего KMEP на Kotlin Multiplatform, см. ниже).
Этот файл — весь контекст, накопленный в работе с другим ассистентом
(Claude), чтобы не начинать с нуля.

## Кто где: разделение ролей

- **Ты (агент в терминале)**: выполняешь команды, пишешь/правишь код,
  тестируешь, итерируешь.
- **Владелец проекта**: передаёт тебе задачи и твои результаты дальше
  на ревью, сам не пишет код.
- **Claude (в чате)**: ревьюит твои результаты, ловит ошибки, поправляет
  архитектурные решения. Если что-то пошло не так — владелец покажет
  твой вывод Claude, тот скажет, что поправить, и это вернётся тебе.

Не удивляйся, если через какое-то время придёт правка "со стороны" —
это нормальный процесс ревью, не твоя ошибка по умолчанию.

## Общая цель проекта

Vidora — Flutter YouTube-клиент. Сейчас работает на **NewPipeExtractor**
(Kotlin-библиотека, уже подключена и рабочая — НЕ трогать, она не часть
этой задачи). Параллельно строим `kmep-proto` — Dart-прототип
альтернативного экстрактора, чтобы проверить архитектурные решения
(мультиклиентный fallback, circuit breaker, remote config) на реальном
трафике, прежде чем вкладываться в постройку **публичного** KMEP —
отдельной библиотеки на Kotlin Multiplatform для стороннего сообщества
разработчиков (namespace `com.vidora.kmep`), которая должна стать
"эволюцией NewPipeExtractor". Это отдельная, более поздняя задача —
сейчас фокус только на `kmep-proto`.

Критерии, по которым поймём, что прототип готов к переносу в KMP:
3-4 недели в проде, success rate экстракции ≥95%, пережил минимум одно
реальное изменение YouTube без полного отказа, есть подтверждённые случаи
что fallback-логика (не останавливаться на первом успешном клиенте, если
качество ниже порога) реально даёт лучший результат.

## Структура репозитория

```
vidora_kmep/
├── dart/
│   ├── lib/
│   │   ├── kmep.dart                       # публичный barrel-экспорт
│   │   └── src/
│   │       ├── models/kmep_models.dart     # VideoInfo, KMEPStream, ошибки
│   │       ├── clients/                    # InnerTubeClient + 4 конфига (ANDROID_VR/IOS/WEB_SAFARI/TV)
│   │       ├── parsers/player_parser.dart  # playerResponse -> VideoInfo
│   │       ├── resolvers/stream_resolver.dart  # sig/nsig-аплайер найден и встроен, см. ниже
│   │       └── core/                       # ExtractionOrchestrator, RemoteConfig, CacheManager
│   ├── test/player_parser_test.dart        # юнит-тесты, dart test должен проходить
│   ├── tool/                               # диагностика; актуальные: verify_prod_pipeline.js и др., см. ниже
│   └── pubspec.yaml                        # ЧИСТЫЙ Dart-пакет, БЕЗ Flutter-зависимостей — не добавляй flutter_js сюда
├── flutter_integration/flutter_js_runtime.dart  # FlutterJsRuntime, flutter analyze чист (см. ниже)
└── backend/                                # Python fallback backend, не активная задача сейчас
```

## ГЛАВНАЯ ЗАДАЧА: найти n-sig entry point — РЕШЕНА (2026-08-22)

### Итог: отдельной функции "n-строка -> n-строка" в player.js НЕТ

Брутфорс `find_nsig.js` (4263 кандидата против реального n) дошёл до конца
и НЕ нашёл трансформер среди строковых функций — все 11 прошедших фильтр
были ложными (nonce-генераторы, hex-конвертеры и т.п.). Причина: в текущих
сборках sig+nsig встроены в функции, работающие с ЦЕЛЫМ URL через
внутреннюю обёртку `g.iO`. Их маркер (по нему их находит и солвер yt-dlp):
в теле есть вызов `X.Y("alr","yes")` (guard "already rewritten").

Найденная функция в этой сборке — **`ji`** (локал замыкания IIFE):

```js
ji = function(t, f = "", H = "") {
  t = new g.iO(t, !0);           // URL-обёртка
  t.set("alr", "yes");
  H && (H = ne(4,8460,Ze(51,3621,H)),  // дешифровка сигнатуры
        t[J[4]](f, Rz(13,2861,H)));    // установка под именем f (=sp)
  return t;
}
```

Контракт: `ji(urlString, sigParamName, rawSig)` -> объект `g.iO`, у которого
`.KW()` ЛЕНЬВО сериализует итоговый URL: дешифрованная подпись кладётся под
`sigParamName`, а n трансформируется при сериализации. Работает и БЕЗ
подписи (`ji(url,'','')`) — n всё равно трансформируется, это путь для
форматов с прямым url (клиенты без signatureCipher).

### Как это проверялось (инструменты в tool/, все рабочие)

- **`fetch_challenge.js`** — общий модуль: свежий WEB playerResponse ->
  `{itag, sp, s, n, innerUrl}` первого формата с signatureCipher.
- **`probe_nsig_pipeline.js <videoId>`** — полный прогон: bootstrap шима +
  дампа (с расширенным коллектором замыкания: и `=class`, и `function NAME`),
  вызов ji с реальными данными, Range-запрос на итоговый URL.
  Ожидание: **HTTP 206 video/mp4**.
- **`solve_with_ytdlp.js`** — эталонная сверка: скармливает НАШ дамп и НАШ
  challenge официальному ejs-солверу yt-dlp (lib/core скрипты из пакета
  `yt-dlp-ejs`, заранее выгружены в `/tmp/opencode/ejs_*.js`; если /tmp
  чист — пересоздать командой из docs ниже). Результат совпал С нами
  БАЙТ-В-БАЙТ по обоим челленджам (n и s) — трансформации корректны.
  Пересоздание эталонных скриптов:
  ```bash
  python3 -c "from yt_dlp_ejs.yt import solver; \
    open('/tmp/opencode/ejs_lib.js','w').write(solver.lib()); \
    open('/tmp/opencode/ejs_core.js','w').write(solver.core())"
  ```
  (нужны `pip3 install yt-dlp-ejs`; самому yt-dlp при этом нужен
  `--js-runtimes node` — по умолчанию включён только deno!)
- **`verify_prod_pipeline.js <videoId>`** — ГЛАВНАЯ ПРОВЕРКА ПРОД-КОДА:
  извлекает реальные константы из `stream_resolver.dart` (discovery-скрипт,
  формат выражения), бутстрапит их против живого дампа, зовёт, делает
  Range-запрос. Ожидание: `__kmepResolveFn найден: ДА`, затем HTTP 206.

### Что изменилось в проде

`StreamResolver` переписан под реальность (старые хуки
buildSigCallExpression/buildNsigCallExpression удалены — таких точечных
функций не существует):

1. `_ensureBootstrapped`: после патча `window=this` инжектит КОЛЛЕКТОР
   выгрузки замыкания (`__closureFns`, регэкспы: `NAME=function`,
   `NAME=class`, `function NAME(`) и **discovery-скрипт**: ищет аплайер
   ПОВЕДЕНЧЕСКИ (маркер `"alr"`+`"yes"` в Function.prototype.toString,
   предпочтение создающим `new g.iO(`, dry-run на dummy googlevideo-URL:
   вернул объект с .KW(), в строке есть alr=yes, n изменился). Имя функции
   между релизами меняется — поэтому никаких хардкодов имён.
2. Один вызов JS на формат: `_resolveUrlViaPlayerJs(url, sp, sig)` —
   cipher-формат передаёт sp/s из signatureCipher, прямой — пустые строки.
   Форматы без cipher И без n идут насквозь без JS.
3. Юнит-тесты в `test/player_parser_test.dart` (группа StreamResolver):
   фейковый JsRuntime, пути cipher/direct/clean, кэш бутстрапа, оборачивание
   ошибок в KMEPErrorCode.nsigFail. `dart test` — 11 passed.

### Грабли, о которых надо помнить

- **Вызов ровно ОДИН раз на URL.** Повторный прогон уже обработанного URL
  трансформирует n ещё раз -> ссылка невалидна. alr=yes от этого НЕ
  защищает (проверено: второй прогон меняет n).
- Имя параметра подписи берётся из `sp` поля signatureCipher (сейчас
  `"sig"`, раньше был `"signature"`) — НЕ хардкодить.
- Длина n ПОСЛЕ трансформации может отличаться от входной (16 -> 14) —
  это нормально для текущих сборок.
- ANDROID/IOS клиенты в `find_nsig.js` по-прежнему дают FAILED_PRECONDITION
  (не чинили, работаем через WEB + signatureTimestamp).

## Следующие шаги (бывшая главная задача закрыта)

### WebViewJsRuntime на устройстве: PASS (2026-08-23, сессия v11-v14)

On-device харнес (kmep_proto_harness, APK через CI
`.github/workflows/build_harness_apk.yml`, артефакт `kmep-proto-harness-apk`)
прошёл ОБЕ стадии: A) ANDROID_VR baseline 27 форматов maxH=2160; B) n-тест
на живом player.js в headless WebView: `2w9J-B1FRC9th79L` ->
`hijUNSr2Sb4f-A` == эталон Node. Контекст: origin youtube.com корректный,
встроики целы, коллектор выгрузил fns=4090, discovery выбрал `ji`.

**ГЛАВНАЯ ГРАБЛЯ (стоит дня): обёртка вызова для evaluateJavascript.**
Форма `(function(){try{ var r=(function(){EXPR})(); return ... })()`
(вложенная IIFE вокруг выражения) НА ANDROID МОЛЧА ВОЗВРАЩАЕТ r=undefined —
даже для кода с безусловным `return String(...)`. Никаких исключений,
мост отдаёт честный JSON с пустой строкой; легко принять за «discovery не
сработал» или «бридж сломан». РАБОЧАЯ форма — плоская:
`(function(){try{ var r=(EXPR); return JSON.stringify(...) })()`.
Правило: не оборачивать пользовательское выражение в дополнительную
функцию, подставлять как есть.

Вторые грабли: flutter_inappwebview сам делает json.decode ответа один раз
(строка -> String), наш код декодирует второй раз; принимаем обе формы
(String|Map) в `_decodeResult`. Санити discovery сравнивал строку с
'missing' — мусорный '' проходил как ложный PASS; теперь структура
(envSnapshot: echo/origin/strOk/jsonOk/fns/fn) и пустой результат call()
— громкое исключение с repr сырого ответа моста.

Следующий шаг: перенести WebViewJsRuntime из харнеса в прод-приложение
(flutter_inappwebview уже совместим по AGP 8.7.3+), заменив
FlutterJsRuntime (QuickJS падает на player.js: "unconsistent stack size").

### Харнес v15: этап C — полный StreamResolver e2e (готов к прогону, 2026-08-23)

Коммит `9305906`, kmep_proto_harness/lib/main.dart. После A (baseline) и
B (n-тест на ассете) добавлена стадия C — ровно запрошенный e2e:

- **C1**: `HttpWatchPageMetaProvider` -> STS + URL актуального player.js.
- **C2**: реальный `InnerTubeClient(WEB)` c STS -> сырые форматы. Если WEB
  не ОК/без url-форматов — фолбэк источника на ANDROID_VR (прямые url с n,
  резолвер гоняет их через пустые sp/s).
- **C3**: ПРОДАКШЕН-`StreamResolver` на СВЕЖЕМ `WebViewJsRuntime`:
  fetchPlayerJs качает player.js ПО СЕТИ (~2.5 МБ), bootstrapParts гонит
  shim+player+discovery через WebView, resolve() обрабатывает ВСЕ форматы.
  Логируются размер player.js, fns/fnName из envSnapshot, вход->выход.
- **C4**: Range-чек bytes=0-1023 КАЖДОГО готового URL; PASS = streams>0 и
  доля 2xx >= 80% (корректный n даёт 206, битый — 403).
- Рантаймы B и C теперь dispose'ятся в конце прогона (раньше текли при
  повторных нажатиях кнопки).

Десктопная репетиция того же потока (NodeProcessJsRuntime, tool-скрипт
жил временно, удалён): C1 STS=20683, C2 WEB OK 27 форматов (26 SABR + itag18
signatureCipher), C3 player.js=2567494 resolve 27->1, C4 HTTP 206 PASS.
Ожидание на устройстве: тот же поток через WebView; SABR-only у WEB — норма.

ВАЖНО для владельца: из среды агента нет кредов GitHub (`gh` отсутствует) —
APK v15 собирается после ПУША владельца в main (workflow
build_harness_apk.yml, артефакт kmep-proto-harness-apk).

#### РЕЗУЛЬТАТ ПРОГОНА v15 на устройстве: A/B/C ВСЕ PASS (2026-08-23)

- A[385 ms]: ANDROID_VR 27 форматов, прямых=27, maxH=2160, HTTP 200.
- B: bootstrap ассета 1884 ms; env чистый (echo=42, origin youtube.com,
  fns=4090); маркер OK; call(ji+KW) 19 ms; n `2w9J-B1FRC9th79L` ->
  `hijUNSr2Sb4f-A` == эталон.
- C1[1091 ms]: STS=20683, player.js=/s/player/2574220e/.../base.js — ТОТ ЖЕ
  билд, что десктопу в репетиции (размер совпал байт-в-байт: 2567494).
- C2[579 ms]: WEB status=OK, форматов=27, с-url=1 (itag18 cipher),
  требуют-playerJs=1 — телефон и датацентр дают ОДИНАКОВУЮ картину SABR:
  доминирование SABR у WEB — свойство клиента, не IP-репутации.
- C3[2064 ms]: скачивание player.js по сети + бутстрап свежего WebView +
  discovery + resolve ВСЕХ форматов; fns=4090, fn="ji"; вход 27 -> готово 1.
- C4[808 ms]: itag18 Range bytes=0-1023 -> **HTTP 206**; 2xx=1/1 -> PASS.

Нюанс для будущих разборов: probe показал, что `get("n")` на объекте,
вернутом ji(), УЖЕ даёт трансформированный n ДО вызова KW() — т.е.
трансформация выполняется при КОНСТРУИРОВАНИИ g.iO внутри ji(), а KW()
только сериализует. Формулировка «KW лениво трансформирует» из старых
заметок неточна; правило «вызывать ровно один раз на URL» не меняется.

### Прогресс по шагам (обновлено 2026-08-23, ночная сессия — ПОЧТИ ВСЁ ЗАКРЫТО)

1. ~~JsRuntime~~ — NodeProcessJsRuntime + FlutterJsRuntime.
   **FlutterJsRuntime теперь покрыт юнит-тестами** (`flutter test` в
   flutter_integration/ — 5 тестов: санити discovery, маркер ошибок,
   порядок вызовов, запрет call до bootstrap). Пакет оформлен как
   `flutter_integration/pubspec.yaml` (path-dep на ../dart).
   На устройстве по-прежнему не гонялся.
2. ~~Живой прогон~~ / метрики / **POT-интеграция ЗАВЕРШЕНА**:
   - Поднят сервер bgutil (`node build/main.js`, порт 4416): холодный
     токен ~5 c, из кэша 0.4 c (скрипт-режим был 10-20 c).
   - Реализованы `BgutilScriptPoTokenProvider` и
     `BgutilHttpPoTokenProvider` (+ тесты на фейковых скрипте/сервере).
   - **НАЙДЕН И ПОЧИНЕН КОРНЕВОЙ БАГ 74% urlRejected**: WEB+POT отдаёт
     itag18 КАК ПРЯМОЙ url с сырым n; оркестратор резолвил только cipher,
     прямые проходили нетронутыми -> CDN 403. Теперь условие резолва:
     cipher ИЛИ прямой url с параметром n (тест добавлен).
   - Биндинг токена: для этой сессии YouTube включил эксперимент
     html5_generate_content_po_token -> GVS-токен биндится к videoId
     (подтверждено логом yt-dlp). Провайдеры поддерживают переопределение
     биндинга через resolver (для WEB без эксперимента нужен visitorData).
3. ~~Финальные метрики~~ — **SUCCESS RATE 98% (49/50)** на той же выборке,
   что давала 2%: ok=49, botCheck=1, urlRejected=0. Критерий >=95% из
   брифа ДОСТИГНУТ (на датацентровом IP с POT). Прогресс A/B/C:
   без POT 2% -> POT+баг 24% -> POT+фикс 98%.
   e2e_orchestrator с --pot-http: 2/2 ранее падавших видео OK (206/200).
4. RemoteConfig — client_overrides + **HttpRemoteConfigFetcher**
   (core/infra.dart) + DiskPlayerJsCache (кэш player.js на диск).
   Всё покрыто тестами (29 passed в dart/).
5. ~~PO token~~ — готово целиком (см. п.2).
6. Резидентный IP — недоступно из этой среды; КОМАНДЫ ДЛЯ ЗАПУСКА ГОТОВЫ:
   ```bash
   # на машине с резидентным IP:
   cd dart && dart run tool/metrics_batch.dart 50 --pot-http=<bgutil-host>:4416
   # без POT (для сравнения):
   cd dart && dart run tool/metrics_batch.dart 50
   ```
7. SABR — РЕШЕНИЕ: вне скоупа kmep-proto. С SABR-only ответами (без URL)
   сейчас честно падаем с "No streams"; POT часто превращает их в ответы
   с прямыми itag18-URL, чего прототипу достаточно.

### Как поднять POT-сервер (для воспроизведения)

```bash
git clone --depth 1 https://github.com/Brainicism/bgutil-ytdlp-pot-provider /tmp/bgutil
cd /tmp/bgutil/server && npm install --ignore-scripts && npx tsc
setsid nohup node build/main.js > /tmp/bgutil.log 2>&1 < /dev/null &
curl http://127.0.0.1:4416/ping   # {"server_uptime":...,"version":"1.3.2"}
# затем: dart run tool/e2e_orchestrator.dart --pot-http [videoId...]
```

### Архив: детали пятой сессии (конфиги клиентов, POT-абстракция — всё ещё актуально как справка)

1. ~~JsRuntime~~ — NodeProcessJsRuntime (десктоп) + **FlutterJsRuntime**
   (`flutter_integration/flutter_js_runtime.dart`): flutter_js
   (QuickJS/Android, JavaScriptCore/iOS). ПРОВЕРЕНО `flutter analyze`
   против реального flutter_js ^0.8.3 + нашего пакета в скретч-проекте —
   чисто. Ошибки JS перехватываются внутри движка маркером __KMEP_ERR__
   (не зависим от форматирования исключений мостом), bootstrap делает
   санити-проверку что discovery нашёл аплайер. НЕ проверено на устройстве
   (нужен Android/iOS) — первый пункт проверки при интеграции в Vidora.
   Таймаутов нет: зацикленный JS блокирует поток — вызывать из isolate.
2. ~~Живой прогон~~ — e2e_orchestrator.dart / e2e_live_test.dart.
3. ~~Оркестратор замкнут~~ (+ исправление пустых url в парсере).
4. ~~RemoteConfig client_overrides~~ — RemoteConfig.clientOverrides:
   {"IOS": {"clientVersion": ...}} мержится на дефолты через
   ClientRegistry.resolved(id, overrides) (copyWith); неизвестные ключи
   и неизвестные id безопасны; оркестратор использует resolved-конфиги.
   Юнит-тесты: override доходит до HTTP-заголовков.
5. ~~Метрики~~ — metrics_batch.dart, 50 видео: 2% ok / 86% botCheck /
   12% urlRejected (=403 CDN на корректно извлечённом itag18). Вывод:
   логика работает, потолок задаёт антибот — нужен PO token или
   резидентный IP для честных чисел.
6. ~~PO-token абстракция~~ — core/po_token.dart: PoTokenProvider +
   NoOpPoTokenProvider; оркестратор кладёт токен (кэш на видео) в тело
   player-запроса (serviceIntegrityDimensions.poToken) и параметром pot=
   в googlevideo-URL (только gv-хосты). РЕАЛЬНОГО ГЕНЕРАТОРА ТОКЕНОВ НЕТ:
   следующий большой шаг — bgutils через Python backend или BotGuard в
   FlutterJsRuntime. Тесты: токен доходит до тела и до URL; NoOp ничего
   не портит.
7. **Конфиги клиентов = точные реплики yt-dlp 2026.08**
   (tool/client_matrix_ytdlp.js): ВСЕ клиенты теперь keyless (ключи не
   нужны вообще); ANDROID_VR 1.65.10 проверен живьём (прямые url, 206);
   IOS 21.26.4 стал ВАЛИДНЫМ запросом (был FAILED_PRECONDITION), без POT
   отдаёт только SABR-дескрипторы; WEB_SAFARI это обычный WEB с Safari-UA;
   TV 7.20260707 требует visitorData.

### TV + visitorData: расследование (2026-08-22, шестая сессия)

- Источник visitorData у yt-dlp: ytcfg watch-страницы (VISITOR_DATA) или
  responseContext.visitorData любого API-ответа; передаётся заголовком
  X-Goog-Visitor-Id.
- Проверено живьём: TVHTML5 7.20260707 + visitorData из ytcfg в
  context.client.visitorData ДАЛ OK 27 форматов 2160p РОВНО ОДИН РАЗ.
  Все последующие пробы (все размещения: client/context/header; свежие
  visitorData; двухшаговая схема с responseContext.visitorData) —
  UNPLAYABLE "page needs to be reloaded". Вывод: форма запроса верная,
  но TVHTML5 с датацентрового IP гейтится антиботом почти всегда — та же
  история, что с POT. Реанимировать TV без резидентного IP не вышло.
- ВАЖНО: TVHTML5 ломается от playbackContext.signatureTimestamp (дважды
  подтверждено) — у TV needsSignatureTimestamp УБРАН, только visitorData.
- Инфраструктура реализована и протестирована: WatchPageMeta.visitorData
  (ytcfg, с JSON-раскодированием), InnerTubeClientConfig.needsVisitorData,
  InnerTubeClient.fetchPlayer(visitorData:) -> context.client.visitorData +
  X-Goog-Visitor-Id, оркестратор прокидывает из меты. Когда IP будет
  резидентный — TV может заработать без дополнительных изменений кода.



### PO-политики клиентов (из yt-dlp, для планирования)

- tv: POT НЕ требуется вовсе -> самый перспективный фолбэк при наличии
  visitorData (см. расследование выше — гейтится репутацией IP).
- ios / android_vr / web / web_safari: POT требуется для https/dash
  стримов; анфорсмент плавающий по IP (наш датацентровый ловит почти
  всегда).

### МЕТРИКИ SUCCESS RATE (2026-08-22, выборка 50 видео через поиск)

Инструмент: `dart run tool/metrics_batch.dart [кол-во] [файл-с-id]`
(сам собирает выборку по 10 категориям поиска, гоняет полный оркестратор,
классифицирует отказы, пишет /tmp/opencode/kmep_metrics.json).

Результат на датацентровом IP БЕЗ PO token:
- ok            1   2.0%   (санити-якорь dQw4w9WgXcQ — стабильно зелёный)
- botCheck     43  86.0%   (InnerTube: "Sign in to confirm you're not a bot")
- urlRejected   6  12.0%   (WEB itag=18 извлечён ПРАВИЛЬНО, но googlevideo
                            отдал 403 — тот же бот-чек, но на слое CDN)

ВЫВОД ДЛЯ РЕШЕНИЯ О KMP: экстракционная логика работает безупречно везде,
где InnerTube вообще отдаёт форматы; потолок success rate определяется
РЕПУТАЦИЕЙ IP / PO token'ами, а не нашим кодом. Следующий шаг для честных
метрик — запуск с резидентного IP или PO-token провайдер (yt-dlp решает
это так же). Без этого метрики измеряют YouTube-антибот, не нас.



### НОВОЕ ВАЖНОЕ ОТКРЫТИЕ: WEB почти полностью перешёл на SABR

У WEB клиента из streamingData приходят: `formats` (только легаси itag=18
с signatureCipher), `adaptiveFormats` — ДЕСКРИПТОРЫ БЕЗ URL (metadata для
SABR: initRange/indexRange/bitrate...) и `serverAbrStreamingUrl`. То есть
полноценный WEB-fallback требует реализации SABR/USTREAMER протокола — это
большая отдельная задача, в kmep-proto сознательно НЕ делаем. Пока SABR не
реализован, единственный клиент с прямыми URL — ANDROID_VR.

### Грабли этой сессии

- В конфигах клиентов clientName для ТЕЛА ('ANDROID_VR', строка) и для
  ЗАГОЛОВКА X-YouTube-Client-Name ('28', число) — разные поля
  (bodyClientName/headerClientName), не путать.
- IOS стабильно FAILED_PRECONDITION (пробовали: ключи/без ключа/новые
  версии/deviceModel/visitorData). ТВ нужен visitorData (без него
  UNPLAYABLE "page needs to be reloaded"). WEB_SAFARI отвергается API по
  enum client_name. Все три — в реестре есть, в дефолтном приоритете их
  можно держать последними, падают быстро и gracefully.
- Бот-чек "Sign in to confirm you're not a bot" зависит от видео+IP
  (датацентровый IP ловит его на части контента). Это главный источник
  неудач живого прогона, лечится PO token / резидентными прокси — вне
  скоупа прототипа, но ОБЯЗАТЕЛЬНО учитывать в метриках success rate.
- У помеченных бот-чеком ответов streamingData может быть непустым, но все
  форматы — SABR-дескрипторы: код должен различать "нет форматов" и
  "форматы есть, но прямых URL нет" (в e2e-инструменте различается).

### Что осталось следующим (приоритет)

1. flutter_js-реализация JsRuntime (интерфейс уже обкатан
   NodeProcessJsRuntime'ом; discovery-скрипт и выражения переиспользуются
   как есть).
2. Метрики success rate на большой выборке (50+ видео) с разделением по
   причинам отказа: бот-чек / SABR-only / сеть — данные для решения о
   переносе в KMP.
3. RemoteConfig: приоритет клиентов и пороги качества из конфига.
4. Подумать про PO-token провайдера (BGP/gvsPoToken) — без него бот-чек
   будет ограничивать success rate на серверных IP.

### Инструменты, добавленные во второй сессии

- `tool/e2e_orchestrator.dart` — живой прогон через полный оркестратор
  с Range-чеком лучшего стрима.
- `tool/e2e_live_test.dart` — по-клиентная матрица с success rate.
- `tool/metrics_batch.dart` — МЕТРИКИ на большой выборке (поиск по 10
  категориям или файл с id), классификация отказов
  (botCheck/noStreams/apiRejected/urlRejected/ok), JSON-отчёт.
- `tool/client_matrix.js` — калибровка конфигов InnerTube-клиентов.
- `tool/debug_web_resolve.dart` — поглавная судьба форматов в resolve().

### Предыдущий контекст (архив, уже не актуально как задача)

### Контекст проблемы

YouTube защищает URL стримов параметром `n` в query-строке — его нужно
пропустить через функцию-трансформер, которая живёт внутри `player.js`
(обфусцированный, ~2.5 МБ, меняется от релиза к релизу).

**Пробовали вычленять одну функцию regex'ом — НЕ РАБОТАЕТ.** Актуальный
player.js обфусцирует строковые литералы через общую таблицу с
XOR-обфусцированными индексами (`m[h^8856]` и т.п.) — вырезанная функция
без остального файла не может разрешить зависимости.

**Текущий подход**: выполнить **весь** `player.js` в JS-движке (Node
`vm` для диагностики, `flutter_js`/QuickJS в проде), через browser-shim
(заглушки под `window`/`document`/`navigator`, которых нет в голом JS),
и вызвать уже готовую публичную функцию на `_yt_player` без повторной
загрузки файла на каждое видео.

### Инструменты в tool/ (все уже написаны и рабочие)

- **`player_js_probe.dart`** — качает актуальный `player.js` для видео,
  сохраняет в `player_js_dump.js`. Запуск: `dart run tool/player_js_probe.dart <videoId>`
- **`find_nsig.js`** (Node) — главный рабочий скрипт: сам достаёт
  `INNERTUBE_API_KEY` со страницы, пробует клиентов ANDROID → IOS → WEB
  по очереди, достаёт РЕАЛЬНЫЙ `n`-параметр из настоящего `adaptiveFormats`
  URL, бутстрапит `browser_shim.js` + `player_js_dump.js` в один JS-контекст,
  перебирает ВСЕ функции на `_yt_player` (их будет ~476) и ранжирует
  кандидатов на роль n-sig трансформера по критериям: не падает, возвращает
  строку, длина близка к входу (±3 символа), результат отличается от входа.
  Запуск: `node tool/find_nsig.js <videoId>`
- **`extract_function.js`** — точное извлечение тела функции по имени
  со сбалансированными скобками (не `grep -A N`, который может обрезать
  функцию посередине). Запуск: `node tool/extract_function.js <funcName>`
- **`test_harness.js`** + **`browser_shim.js`** — более простой смок-тест
  шима отдельно от полного пайплайна `find_nsig.js`.

### Что уже нашли и починили (не повторяй эти ошибки)

1. **API-ключ должен быть клиент-специфичным.** Ключ, снятый со страницы
   (`INNERTUBE_API_KEY`), скоуплен под WEB — на ANDROID/IOS даёт
   `FAILED_PRECONDITION`. Для ANDROID в итоге работает запрос **без**
   `?key=` параметра вообще (см. `find_nsig.js`, `noKey: true` для ANDROID).
   IOS/ANDROID пока НЕ проверены до конца успешно — WEB заработал, на
   нём и продолжаем.
2. **WEB даёт `UNPLAYABLE` без `signatureTimestamp`** в теле запроса
   (`playbackContext.contentPlaybackContext.signatureTimestamp`).
   Значение достаётся с watch-страницы: `"STS":(\d+)` в HTML. С этим
   полем WEB отдаёт 27 форматов, статус OK — это подтверждено, работает.
3. **`document.referrer` не должен быть пустой строкой** в шиме — где-то
   в player.js делается `new URL(document.referrer)`, на пустой строке
   это бросает исключение. В `browser_shim.js` уже стоит
   `'https://www.youtube.com/'` — если пишешь новый шим, не забудь это.
4. **Патч `window=this`** (на момент находки был "не проверен", теперь
   ПОДТВЕРЖДЁН — весь пайплайн на нём работает): player.js
   внутри делает `var window=this` в strict-mode функции, вызванной
   обычным вызовом (не `.call()`) — `this` уходит в fallback без
   `.location`, наш `globalThis.window` эта локальная переменная не
   видит:
   ```js
   playerJs = playerJs.replace(/\bwindow=this\b/g, 'window=globalThis.window');
   ```
   Это есть и в `find_nsig.js`, и в `test_harness.js`, и в Dart-версии
   (`stream_resolver.dart`, метод `_ensureBootstrapped`).

### Твой следующий шаг

1. Убедись что `player_js_dump.js` свежий (или перекачай:
   `dart run tool/player_js_probe.dart dQw4w9WgXcQ`).
2. Запусти `node tool/find_nsig.js dQw4w9WgXcQ`.
3. **Ожидание**: с патчем `window=this` player.js должен выполниться до
   конца без исключений, и скрипт должен дойти до шага 4 (перебор
   кандидатов). Если снова упадёт — в выводе будет `Stack: player.js:LINE`,
   найди эту строку в `player_js_dump.js` (`sed -n 'LINEp' player_js_dump.js`
   не сработает, файл — одна строка; используй `node tool/extract_function.js`
   подход или просто `grep -o` с контекстом вокруг характерного фрагмента
   ошибки) и разбирайся аналогично уже пройденным случаям выше.
4. Если дошло до перебора кандидатов — получишь топ-10 функций с их
   `n -> результат`. **ВАЖНО**: не верь автоматически первому кандидату.
   Раньше уже был ложный срабатывание (`eAO`, которая на деле оказалась
   парсингом версии плеера — возвращала МАССИВ через `split(".").reverse()`,
   а не строку через `split("").join("")`). Проверь: (а) возвращает
   строку той же длины что и вход, (б) `extract_function.js <name>`
   на тело — реальный nsig-transform выглядит как цепочка вызовов
   `X.aa(a,N);X.bb(a,M);...;return a.join("")` где X — вспомогательный
   объект с мелкими array-операциями (reverse/splice/swap).
5. Когда кандидат найден и проверен — пропиши его в `StreamResolver`
   (`buildNsigCallExpression`) как рабочее выражение вида
   `(n) => '_yt_player.НАЙДЕННОЕ_ИМЯ("$n")'`.

## ОТДЕЛЬНОЕ ИССЛЕДОВАНИЕ: on-device POT/BotGuard без сервера bgutil

Параллельная ветка, прод-код НЕ трогает. Вопрос: можно ли генерировать
PO-token (BotGuard challenge -> integrity token -> минтинг) целиком на
устройстве через WebViewJsRuntime, без стороннего bgutil-сервера.
Эксперименты живут в `/tmp/opencode/pot_research/` (в репо попадут только
после ревью и рабочего плана).

### Разбор референса: bgutil 1.3.2 + bgutils-js 4.0.3 (session_manager.ts)

Полный пайплайн из 5 шагов (все HTTP — обычные запросы, JS нужен только
для шагов 2/3/5):

1. **Челлендж — только с главной страницы.** GET `https://www.youtube.com/`
   -> из HTML достаём `ytcfg.set({...})` (кладём как `yt.config_` — VM читает
   `yt.config_.EVENT_ID`) и вызов `window.ytAtN({...})` -> `.R.bgChallenge`
   = `{program, globalName, interpreterUrl.privateDoNotAccessOrElse...
   WrappedValue, interpreterHash}`.
   **ВАЖНО (патч unstem 2026-08 прямо в нашем клоне bgutil):** челленджи с
   `/youtubei/v1/att/get` теперь ОТКЛОНЯЮТСЯ — рабочий источник только
   главная страница (`getChallengeFromHomepage` приоритетнее, `/att/get`
   оставлен как легаси-фолбэк). Для on-device это УДОБНО: watch/homepage
   страницы мы и так умеем качать, отдельного att/get не нужно.
2. **Интерпретатор VM**: скачать `https:` + interpreterUrl (gstatic,
   boq-botguard-sfs скрипт), выполнить в контексте с DOM-шимом; ПЕРЕД этим
   в глобал кладётся `yt = {config_: <ytcfg>}` (+ то же на window).
3. **Snapshot**: `globalObject[globalName].a(program, setupCb, true,
   undefined, telemetryCb, [[],[]], undefined, false, loggerFns)` ->
   массив, `[0]` = СИНХРОННАЯ snapshot-функция; вызов
   `fn([contentBinding, undefined, webPoSignalOutput=[], undefined])->
   botguardResponse` (строка). Есть и асинхронный путь через setupCb
   (Promise + setTimeout, дефолтный таймаут 3000 мс).
4. **Integrity token**: POST
   `https://jnn-pa.googleapis.com/$rpc/google.internal.waa.v1.Waa/GenerateIT`,
   заголовки: `content-type: application/json+protobuf`,
   `x-goog-api-key: AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw`,
   `x-user-agent: grpc-web-javascript/0.1`; тело `[REQUEST_KEY,
   botguardResponse]`, REQUEST_KEY=`O43z0dpjhgX20SCx4KAo`. Ответ — массив
   `[integrityToken, estimatedTtlSecs, mintRefreshThreshold,
   websafeFallbackToken]`.
5. **Минтинг**: `getMinter = webPoSignalOutput[0]` — это ФУНКЦИЯ, которую
   выдаёт сама VM во время snapshot; `mintCallback = await
   getMinter(base64ToU8(integrityToken))`; `poToken = base64url(await
   mintCallback(new TextEncoder().encode(contentBinding)))`.
   ВСЯ криптография — внутри интерпретатора VM; bgutils-js не использует
   crypto.subtle вовсе: только atob/btoa, TextEncoder, Promise, setTimeout.

Промежуточный вывод по зависимостям: всё нужное JS-стороне есть в WebView
из коробки (настоящие window/document/navigator c origin youtube.com —
даже точнее jsdom, под которым гоняет bgutil). Единственная архитектурная
дыра — АСИНХРОННОСТЬ: WebViewJsRuntime.call() синхронный, для шагов 3/5
нужен мост «запустить в globalThis -> поллинг статуса повторными call()».
Плюс найден бонус: `createColdStartToken()` в bgutils-js — чистый JS без
VM/integrity token (работает пока sps==2) — кандидат в аварийный фолбэк.

(Продолжение по мере экспериментов — см. ниже.)

### Эксперименты (сессия R1, 2026-08-23 вечер) — ВОСПРОИЗВЕДЕНО БЕЗ СЕРВЕРА

Всё живёт в `/tmp/opencode/pot_research/`. Ключевой скрипт — `bg_full2.js`
(~250 строк, самодостаточный референс всего пайплайна).

**R1. Полный цикл воспроизведён на Node без единой строки bgutil-кода.**
homepage -> челлендж -> интерпретатор -> snapshot -> GenerateIT -> минтинг
-> токены для обоих биндингов. Числа живого прогона:
- homepage ~850 KiB, челлендж `program` ~38 KiB, интерпретатор **62 KiB**
  (`https://www.google.com/js/th/<hash>.js` — НЕ большой gstatic);
- eval интерпретатора ~60 мс; snapshot под jsdom 4–12 с (медленно! это
  главный кандидат на оптимизацию/замер на устройстве);
- GenerateIT: integrity token ~90 симв., **ttl=43200 c (12 ч)** — минтер
  живёт сессию, кэшировать;
- размер POT: биндинг visitorData ~600–808 симв. base64url, биндинг
  videoId ~158 симв.;
- ОДИН snapshot обслуживает много биндингов подряд (проверено: vd главной
  + несколько videoId из одного минтера).

**R2. Негативный контроль — ГЛАВНОЕ ДОКАЗАТЕЛЬСТВО.** GenerateIT
отвечает HTTP 400 (`Invalid value`) на мусорную строку, пустой ответ И на
деградированный hex-ответ из наших ранних шим-прогонов. Наш настоящий
snapshot он ПРИНЯЛ и выдал integrity token => выполнение BotGuard
прошло серверную валидацию Google. Токен не «похож на настоящий» — он
прошёл проверку сервера, который видит разницу.

**R3. Почему шим не прошёл (и почему это не проблема для WebView).**
VM молча скорит окружение: при «недобором» возвращает деградированный
ответ (hex, `$`-формат но без минтера). Proxy-трассировка доступов
(`full_access_log2.js`, `value_diff.js`) показала, что VM зондирует
антибот-маркеры (`navigator.webdriver`, `document.$cdc_asdjflasutopfhvcZLmcfl_`,
`$wdc_`, `__webdriver_script_fn`) и богатую поверхность navigator
(hardwareConcurrency, deviceMemory, maxTouchPoints, plugins, connection,
mediaDevices, userActivation, keyboard, languages...). Обогащённый шим
(shim_v2) всё ещё не добирает баллов, а вот **jsdom проходит стабильно
(десятки прогонов, wpo=1 всегда)**. Настоящий Android WebView по поверхности
строго богаче jsdom — риск скоринга на устройстве оцениваю как низкий,
закрывается стадией C харнеса.

**R4. Ротация/тайминги — ложные следы.** Подозрения на ротацию программ
и гонку «DOM не устаканился» проверены матрицами (`rotation_test.js`,
`settle_shim.js`): программы меняются каждый запрос (38 KiB ± ), но все
совместимы; задержки перед eval ничего не меняют ни для jsdom, ни для
шима. Единственный стабильный фактор — полнота DOM/navigator.

**R5. Верификация против CDN сегодня НЕинформативна**: текущий IP этого
окружения не гейтится (Range даёт 206 даже без pot=). Эксперимент
html5_generate_content_po_token сегодня выключен (прямых URL у WEB нет).
Поэтому конечное подтверждение «CDN принимает наш pot» остаётся за
стадией C на устройстве (мобильные IP гейтятся охотнее) — либо за
будущими прогонами с датацентрового IP, где гейтинг активен.

Бонус-находка: `createColdStartToken()` в bgutils-js — чистый JS без VM
и integrity token (работает пока sps==2). Кандидат в аварийный фолбэк,
не проверен.

### Рабочий план интеграции on-device POT (сформулирован до реализации)

Архитектура повторяет разделение StreamResolver'а: сеть в Dart,
JS только для вычислений.
1. Сеть (Dart): homepage -> ytcfg + `window.ytAtN` (looseJSON-парсер),
   интерпретатор, POST GenerateIT (константы выше).
2. JS (тот же WebViewJsRuntime, что для player.js): glue-скрипт со
   state machine в globalThis (`__kmepBgStart/Snapshot/Mint/State`),
   мост асинхронности поллингом; snapshot синхронный (array[0]).
3. Dart-провайдер BotGuardJsPoTokenProvider implements PoTokenProvider:
   кэш минтера по integrity token (TTL 12 ч), кэш токенов по биндингу,
   singleFlight от параллельных генераций.
4. Юнит-тесты на фейковом JsRuntime + негативные кейсы R2/R3.
5. Стадия D харнеса on-device.

### НОЧНАЯ СЕССИЯ R2 (2026-08-24): продакшен-реализация ЖИВАЯ, всё зелёное

За ночь план из предыдущего раздела реализован и проверен на живом
YouTube. Изменённые/созданные файлы (для ревью):
- `dart/lib/src/core/botguard_pot_provider.dart` — BotGuardJsPoTokenProvider
  + клей-JS (`botGuardGlueScript`) + parseLooseJson;
- `dart/lib/src/models/kmep_models.dart` — KMEPErrorCode.potFail;
- `dart/lib/kmep.dart` — экспорт провайдера;
- `dart/test/botguard_pot_provider_test.dart` — 8 юнит-тестов;
- `dart/tool/pot_js_e2e.dart` — живая диагностика по шагам;
- `dart/tool/e2e_orchestrator.dart` — флаг `--pot-js`;
- `kmep_proto_harness/lib/main.dart` — v16 со стадией D (on-device POT).

**Починено при верификации (было сломано в первой редакции):**
1. `parseLooseJson`: висячие запятые убирались через
   `replaceAll(re, r'$1')` — у Dart замена ЛИТЕРАЛЬНАЯ, `$1` не
   подставляется (в отличие от JS), в текст втыкался мусорный `$1` и
   весь парсинг челленджа падал. -> `replaceAllMapped`. Это ломало ВСЁ.
2. Тест: колбэк generateItResponder вызывался с неверной арностью
   (компиляция теста).

**Живые прогоны (продакшен-форма, NodeProcessJsRuntime+jsdom):**
- `tool/pot_js_e2e.dart dQw4w9WgXcQ`: POT выдан за 45.6 c холодного
  прогона — из них ~40 c это require(jsdom) на этом ARM-девайсе,
  сам цикл BotGuard ~5 c; ВТОРОЙ токен из той же сессии — **0 мс**
  (маржинальная стоимость минтинга нулевая: mintCallback кэшируется в VM);
  player+POT status=OK 27 форматов; StreamResolver (второй рантайм,
  прод-путь) разрешил itag18; Range 206/206 (IP не гейтится, R5).
- `e2e_orchestrator.dart --pot-js`: **1/1 OK (100%)** через ПОЛНЫЙ
  оркестратор. Первый запуск медленный (~минуты JIT компиляции dart run
  на ARM) — не путать с пайплайном.
- Тесты: dart/ 37 passed; flutter_integration 14 passed; flutter analyze
  харнеса чисто.

**Cold start token (аварийный парашют, /tmp/opencode/pot_research/
cold_start_test.js):** порт createColdStartToken из bgutils-js — чистая
математика БЕЗ VM/integrity token (28 симв для videoId). Round-trip decode
OK; WEB player принимает запрос с ним синтаксически (HTTP 200 OK).
Эффективность на негейтящемся IP проверить нельзя — держать как фолбэк,
проверить на гейтящемся IP вместе со стадией D.

**Стадия D харнеса (v16)**: BotGuardJsPoTokenProvider на СВЕЖЕМ
WebViewJsRuntime без единого шима (настоящий DOM/navigator):
D1 холодный POT + тайминг, D2 маржинальный токен (~мс ожидание),
D3 WEB player запрос с serviceIntegrityDimensions.poToken.
Готова к сборке APK через CI (push в main). ОЖИДАНИЕ: D1 несколько секунд
(настоящий WebView должен быть быстрее jsdom), D2 миллисекунды,
скоринг окружения проходит (R3).

**Что осталось до полного закрытия темы:**
1. Прогнать стадию D на телефоне (APK артефакт CI) — закрывает «скоринг
   в настоящем WebView» и даёт честные тайминги on-device.
2. CDN-приёмка pot= на ГЕЙТЯЩЕМСЯ IP (мобильный/датацентровый) —
   единственный непроверенный рубеж (R5). Критерий: Range без pot= 403 ->
   с pot= 206/200.
3. ~~Воткнуть провайдер в Vidora Beta-бридж~~ УЖЕ СДЕЛАНО (ночная
   сессия Vidora-интеграции, параллельно этой): коммит eb931eb,
   KmepExtractorService -> poTokenProvider: BotGuardJsPoTokenProvider
   на ОТДЕЛЬНОМ WebBridgeJsRuntime (изоляция глобалов от player.js;
   лениво, ANDROID_VR-first токена не требует). Ревью Claude — по
   файлам lib/services/kmep/ и lib/services/extractor_router.dart репо
   Vidora; маршрутизация движков тоже готова (ExtractorRouter с
   фолбэком на NewPipe).

Замечание для ревью: jsdom-часть (`jsdomEnvPart`, путь к модулю) — только
десктопная диагностика внутри tool/, прод её не использует никогда.


## Общие правила работы в этом репо


- `dart/pubspec.yaml` должен оставаться БЕЗ Flutter-зависимостей — весь
  пакет должен собираться голым `dart pub get`/`dart test` без Flutter SDK.
- Любой JS-шим меняешь синхронно в ДВУХ местах: `tool/browser_shim.js`
  (для Node-диагностики) и `browserShimScript` внутри
  `lib/src/resolvers/stream_resolver.dart` (для прод-рантайма) — это
  осознанно два места без общего источника правды, не пытайся их
  объединить, просто держи текст одинаковым.
- Не удаляй `player_js_dump.js` без необходимости — это дорогая (2.5 МБ)
  скачка, используется несколькими скриптами.
- Публичные API-ключи/user-agent строки в коде — это НЕ секреты проекта
  (публичные InnerTube-константы), в отличие от твоих собственных ключей
  (Google OAuth, GitHub-токены и т.п. из других задач) — те никогда не
  клади в код или коммиты.

## Интеграция в Vidora: «Vidora Extractor (Beta)» (2026-08-23, ночь)

Репо ~/vidora (отдельный Flutter-проект), коммит 7914760 в main.
Задача: реализовать заглушку VidoraExtractorBridge.kt на kmep_proto +
WebViewJsRuntime; формат ответов = VideoExtractor.kt (NewPipe), чтобы
переключатель движка не требовал правок вызывающего кода.

### Архитектура (почему так)

  UI ──(vidora_extractor)──> VidoraExtractorBridge.kt
       │ релей+валидация+таймауты          │ хост android.webkit.WebView
       ▼                                   ▲ eval (loadBaseURL youtube.com)
  KmepExtractorService.dart ──(vidora_extractor_web)
  └ ExtractionOrchestrator + WebBridgeJsRuntime (порт логики харнеса)

- **flutter_inappwebview НЕ подключён**: у Vidora AGP 9.0.1, а inappwebview
  6.1.5 с ним несовместим (харнес это ловил и откатывался на AGP 8.7.3).
  Вместо плагина — нативный WebView в бридже: тот же системный движок,
  что прошёл e2e v15.
- Каналы: vidora_extractor (UI->Kt, контракт без изменений),
  vidora_extractor_dart (Kt->Dart релей), vidora_extractor_web (Dart->Kt
  eval). attach() перепривязывает мессенджеры при пересоздании движка.
- WebView/player.js — ЛЕНИВО: дефолтный приоритет RemoteConfig начинается
  с ANDROID_VR (прямые URL), бутстрап 2.5 МБ происходит только если
  клиент отдал cipher/n-форматы.
- Таймауты релея: ping 15 c, search/comments 45/15 c, getStream 120 c
  (холодный прогрев). Ошибки маппятся в коды EXTRACT_FAILED /
  SEARCH_FAILED / COMMENTS_FAILED / BAD_ARGS / TIMEOUT — как у
  VideoExtractor-обработчика в MainActivity.
- getComments -> NOT_SUPPORTED: комментариев в kmep_proto нет; маршруту
  следует откатываться на NewPipe.
- Маппинг VideoInfo -> native: videoStreams {url,resolution "1080p",
  format MPEG_4|WEBM}, audioStreams {url,bitrate,format M4A|WEBMA_OPUS|
  WEBMA} — ровно те строки, что ждёт StreamQuality.bestMp4Audio/
  bestAudioForVideoFormat для MediaMuxer-склейки.
- Поиск: InnerTubeClient.fetchSearch(WEB) + рекурсивный сбор
  videoRenderer/gridVideoRenderer/reelItemRenderer, дедуп по videoId,
  cap 40.

### Проверено / НЕ проверено

- flutter analyze проекта Vidora — чисто по моим файлам; flutter test —
  11 passed (маппинг форматов, парс поиска, дедуп, безопасные дефолты).
- НЕ проверено на устройстве (нет Android SDK в среде агента): реальный
  вызов getStream/search через переключённый движок, поведение системного
  WebView при пересоздании Activity. Первый пункт проверки после сборки.
- Маршрутизация движков (ExtractionEngineService -> кому идти) — сознательно
  НЕ тронута, отдельная сессия.
