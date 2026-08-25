import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/kmep_models.dart';
import '../resolvers/stream_resolver.dart' show JsRuntime;
import 'po_token.dart';

/// Генерация PO token (BotGuard) ЦЕЛИКОМ на устройстве, без сервера bgutil.
///
/// Архитектура повторяет разделение StreamResolver'а: СЕТЬ в Dart
/// (homepage -> челлендж -> интерпретатор -> GenerateIT), ВЫЧИСЛЕНИЯ в JS
/// (выполнение BotGuard-программы VM и минтинг — вся криптография внутри
/// интерпретатора).
///
/// Доказательная база — docs/AGENT_HANDOFF.md, раздел «on-device POT»:
/// R1 (полный цикл воспроизведён без bgutil), R2 (негативный контроль:
/// GenerateIT отличает наш snapshot от мусора => прошла серверную
/// валидацию), R3 (деградация = hex-ответ без '$', у реального WebView
/// поверхность богаче jsdom, который стабильно проходит).
///
/// АСИНХРОННОСТЬ: JsRuntime.call() синхронный, а vm.a/snapshot/минтинг
/// возвращают Promise. Мост — state machine в globalThis.__kmepBgState +
/// поллинг Dart-стороны каждые [pollInterval]. См. _glueScript.
class BotGuardJsPoTokenProvider implements PoTokenProvider {
  final JsRuntime jsRuntime;

  /// GET текста по URL (homepage ~850 KiB, интерпретатор ~62 KiB).
  final Future<String> Function(String url) fetchText;

  /// POST GenerateIT. Инъекция для тестов; по умолчанию — HttpClient.
  final Future<String> Function(Uri url, String body)? postGenerateItOverride;

  /// {videoId: contentBinding} — переопределение биндинга (например
  /// visitorData конкретного видео для WEB без gvs-эксперимента).
  final Map<String, String> Function()? bindingResolver;

  /// Дополнительные bootstrap-части перед glue (инструментально: jsdom-
  /// окружение для десктопных прогонов). Прод не использует.
  final List<String> Function()? extraBootstrapParts;

  final Duration pollInterval;
  final Duration stepTimeout;
  final Duration homepageTimeout;

  BotGuardJsPoTokenProvider({
    required this.jsRuntime,
    required this.fetchText,
    this.postGenerateItOverride,
    this.bindingResolver,
    this.extraBootstrapParts,
    this.pollInterval = const Duration(milliseconds: 100),
    this.stepTimeout = const Duration(seconds: 30),
    this.homepageTimeout = const Duration(seconds: 20),
  });

  // ---- Константы пайплайна (публичные InnerTube/BotGuard константы,
  // те же, что в bgutils-js; НЕ секреты) ----
  static const _generateItUrl =
      'https://jnn-pa.googleapis.com/\$rpc/google.internal.waa.v1.Waa/GenerateIT';
  static const _requestKey = 'O43z0dpjhgX20SCx4KAo';

  /// Публичная константа InnerTube/BotGuard (не секрет) — наружу для
  /// тестов и диагностики.
  static String get requestKeyForTest => _requestKey;
  static const _generateItApiKey = 'AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw';

  /// Диагностика последнего отказа (для логов/стадии C). Контракт
  /// PoTokenProvider — null без исключений, поэтому причина живёт здесь.
  String? lastError;

  // Сессия: ОДИН snapshot обслуживает много биндингов подряд, integrity
  // token живёт ttl (наблюдалось 12 ч) — кэшируем до 0.8*ttl.
  DateTime? _sessionAt;
  int? _sessionTtlSecs;
  String? _integrityToken;
  final Map<String, String> _tokenCache = {};
  Future<String?>? _singleFlight;

  @override
  Future<String?> tokenFor(String videoId) {
    final prev = _singleFlight;
    final run = () async {
      try {
        if (prev != null) await prev; // не молотим параллельно: догоняем
      } catch (_) {}
      return _tokenForLocked(videoId);
    };
    return _singleFlight = run();
  }

  Future<String?> _tokenForLocked(String videoId) async {
    final binding = bindingResolver?.call()[videoId] ?? videoId;
    final cached = _tokenCache[binding];
    if (cached != null) return cached;
    try {
      await _ensureSession();
      await _call('__kmepBgMint(${jsonEncode(_integrityToken)},${jsonEncode(binding)})');
      final st = await _waitFor(const {'potOk'},
          failOn: const {'error'}, what: 'минтинг');
      final pot = st['pot'] as String?;
      if (pot == null || pot.isEmpty) {
        throw KMEPException(KMEPErrorCode.potFail, 'минтинг вернул пустой токен');
      }
      lastError = null;
      return _tokenCache[binding] = pot;
    } catch (e, st) {
      // Стек в lastError: без него деградации вида «String is not a
      // subtype of Map» невозможно локализовать по логам устройства.
      lastError = '$e\n$st';
      return null; // деградация без исключения — контракт PoTokenProvider
    }
  }

  /// Полный цикл сессии (если нет свежей): челлендж -> интерпретатор ->
  /// snapshot -> GenerateIT.
  Future<void> _ensureSession() async {
    final at = _sessionAt;
    final fresh = at != null &&
        _integrityToken != null &&
        _sessionTtlSecs != null &&
        DateTime.now().difference(at) <
            Duration(seconds: (_sessionTtlSecs! * 0.8).floor());
    if (fresh) {
      // Состояние JS могло быть потеряно (пересоздан рантайм) — проверяем.
      // После успешного минтинга фаза остаётся potOk: минтер жив, wpo на месте.
      final phase = await _readPhase();
      if (phase == 'snapOk' || phase == 'potOk' || phase == 'minting') return;
    }

    // S1. Homepage -> ytcfg + челлендж window.ytAtN({...}).R.bgChallenge.
    final html = await fetchText('https://www.youtube.com/')
        .timeout(homepageTimeout);
    final ytcfgMatch =
        RegExp(r'ytcfg\.set\(({.+?})\);', dotAll: true).firstMatch(html);
    if (ytcfgMatch == null) {
      throw const KMEPException(KMEPErrorCode.potFail,
          'homepage: не найден ytcfg.set({...})');
    }
    final ytcfg = jsonDecode(ytcfgMatch.group(1)!) as Map<String, dynamic>;
    final attMatch = RegExp(r'window\.ytAtN\(\s*({[\s\S]*?})\s*\)')
        .firstMatch(html);
    if (attMatch == null) {
      throw const KMEPException(
          KMEPErrorCode.potFail, 'homepage: не найден window.ytAtN({...})');
    }
    final attData = parseLooseJson(attMatch.group(1)!);
    final challenge =
        ((attData['R'] as Map<String, dynamic>?)?['bgChallenge'])
            as Map<String, dynamic>?;
    if (challenge == null ||
        challenge['program'] is! String ||
        challenge['globalName'] is! String) {
      throw const KMEPException(
          KMEPErrorCode.potFail, 'в homepage-ответе нет bgChallenge');
    }
    final program = challenge['program'] as String;
    final globalName = challenge['globalName'] as String;
    final wrapped = (challenge['interpreterUrl']
        as Map<String, dynamic>?)?[
      'privateDoNotAccessOrElseTrustedResourceUrlWrappedValue'
    ];
    if (wrapped is! String || wrapped.isEmpty) {
      throw const KMEPException(
          KMEPErrorCode.potFail, 'bgChallenge без interpreterUrl');
    }

    // S2. Интерпретатор (~62 KiB, google/js/th/<hash>.js).
    final interpJs = await fetchText('https:$wrapped');

    // Bootstrap: glue + yt.config_ + delete старого VM + интерпретатор.
    final envPart = 'try{delete globalThis[${jsonEncode(globalName)}];}catch(e){}'
        'globalThis.yt={config_:${jsonEncode(ytcfg)}};'
        'try{globalThis.window.yt=globalThis.yt;}catch(e){}';
    await jsRuntime.bootstrapParts([
      ...?extraBootstrapParts?.call(),
      _glueScript,
      envPart,
      interpJs,
    ]);

    // S3. Snapshot (синхронный путь через ret[0], Promise-обёртка внутри
    // glue — поллинг разруливает обе формы).
    await _call('__kmepBgStart(${jsonEncode(program)},${jsonEncode(globalName)})');
    await _waitFor(const {'ready'}, failOn: const {'error'}, what: 'vm.a');

    await _call('__kmepBgSnapshot("")');
    final snapSt = await _waitFor(
        const {'snapOk', 'degraded', 'snapNoWpo'},
        failOn: const {'error'},
        what: 'snapshot');
    if (snapSt['phase'] == 'degraded') {
      // R3: VM скорил окружение и вернул деградированный hex-ответ.
      throw const KMEPException(KMEPErrorCode.potFail,
          'BotGuard деградировал (hex-ответ) — окружение неполное');
    }
    if (snapSt['wpoOk'] != true) {
      throw const KMEPException(
          KMEPErrorCode.potFail, 'webPoSignalOutput пуст — минтинг невозможен');
    }

    // S4. GenerateIT.
    final it = await _generateIt(snapSt['response'] as String);

    _integrityToken = it.token;
    _sessionTtlSecs = it.ttlSecs;
    _sessionAt = DateTime.now();
    _tokenCache.clear(); // новый минтер — старые токены чужие
  }

  Future<({String token, int ttlSecs})> _generateIt(String response) async {
    final body = jsonEncode([_requestKey, response]);
    late final raw;
    if (postGenerateItOverride != null) {
      raw = await postGenerateItOverride!(Uri.parse(_generateItUrl), body);
    } else {
      final client = HttpClient();
      try {
        final req = await client.postUrl(Uri.parse(_generateItUrl));
        req.headers.set('content-type', 'application/json+protobuf');
        req.headers.set('x-goog-api-key', _generateItApiKey);
        req.headers.set('x-user-agent', 'grpc-web-javascript/0.1');
        req.headers.set('origin', 'https://www.youtube.com');
        req.headers.set('user-agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0 Safari/537.36');
        req.write(body);
        final resp = await req.close().timeout(stepTimeout);
        raw = await resp.transform(utf8.decoder).join().timeout(stepTimeout);
        if (resp.statusCode != 200) {
          // R2: 400 на мусорном/деградированном ответе — это нормальный
          // отказ валидации, наружу как KMEPException(potFail).
          throw KMEPException(
              KMEPErrorCode.potFail, 'GenerateIT HTTP ${resp.statusCode}');
        }
      } finally {
        client.close();
      }
    }
    final list = jsonDecode(raw) as List<dynamic>;
    if (list.isEmpty || list.first is! String || (list.first as String).isEmpty) {
      throw const KMEPException(KMEPErrorCode.potFail, 'GenerateIT: пустой токен');
    }
    return (
      token: list.first as String,
      ttlSecs: list.length > 1 && list[1] is int ? list[1] as int : 43200
    );
  }

  Future<Map<String, dynamic>> _waitFor(
    Set<String> okPhases, {
    required Set<String> failOn,
    required String what,
  }) async {
    final deadline = DateTime.now().add(stepTimeout);
    while (true) {
      final st = await _readState();
      final phase = st['phase'] as String? ?? 'idle';
      if (okPhases.contains(phase)) return st;
      if (failOn.contains(phase)) {
        throw KMEPException(KMEPErrorCode.potFail,
            '$what: фаза "$phase" ${st['err'] ?? ''}');
      }
      if (DateTime.now().isAfter(deadline)) {
        throw KMEPException(
            KMEPErrorCode.potFail, '$what: таймаут на фазе "$phase"');
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<String> _readPhase() async =>
      (await _readState())['phase'] as String? ?? 'idle';

  Future<Map<String, dynamic>> _readState() async {
    final raw = await _call('__kmepBgState()');
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      throw KMEPException(
          KMEPErrorCode.potFail, '__kmepBgState вернул не JSON: $raw');
    }
  }

  Future<String> _call(String expression) async {
    try {
      return await jsRuntime.call(expression);
    } on KMEPException {
      rethrow;
    } catch (e) {
      throw KMEPException(KMEPErrorCode.potFail, 'JS: $e');
    }
  }
}

/// LooseJSON из инлайн-скриптов homepage: одинарные кавычки, ключи без
/// кавычек, \xNN, висячие запятые, строковые значения с вложенным JSON.
/// Порт parseLooseJSON из pot_research/bg_full2.js 1:1.
Map<String, dynamic> parseLooseJson(String looseJson) {
  var s = looseJson.replaceAllMapped(
      RegExp(r'\\x([0-9A-Fa-f]{2})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
  // ВАЖНО: у Dart replaceAll замена ЛИТЕРАЛЬНАЯ ($1 не подставляется,
  // как в JS) — нужен replaceAllMapped.
  s = s.replaceAllMapped(RegExp(r',\s*([\]}])'), (m) => m.group(1)!);
  s = s.replaceAllMapped(RegExp(r"'((?:[^'\\]|\\[\s\S])*)'"), (m) {
    final inner = m.group(1)!.replaceAll(r"\'", "'");
    return jsonEncode(inner);
  });
  s = s.replaceAllMapped(
      RegExp(r'([{,]\s*)([a-zA-Z0-9_$]+)\s*:'), (m) => '${m.group(1)}"${m.group(2)}":');
  final parsed = jsonDecode(s);
  if (parsed is! Map<String, dynamic>) {
    throw const KMEPException(KMEPErrorCode.potFail, 'looseJSON: не объект');
  }
  parsed.forEach((k, v) {
    if (v is String) {
      final t = v.trim();
      if (t.startsWith('{') || t.startsWith('[')) {
        try {
          parsed[k] = jsonDecode(t);
        } on FormatException {}
      }
    }
  });
  return parsed;
}

/// Клей-JS (одним скриптом, top-level statement'ы через indirect eval):
/// state machine в globalThis + три точки входа для Dart.
///
/// ПОЧЕМУ ТАК: JsRuntime.call() синхронный, все шаги BotGuard возвращают
/// Promise — результаты пишем в B (глобальное состояние), Dart читает
/// поллингом __kmepBgState(). Формы ответов и порядок аргументов сняты с
/// работающего референса pot_research/bg_full2.js (R1):
///   - vm.a(...) -> массив, [0] = snapshot-функция; setupCb даёт
///     асинхронные fns (фолбэк-путь);
///   - snapshot fn([undefined, undefined, wpo=[], undefined]) -> строка,
///     валидная начинается с '$' (иначе деградация, см. R2/R3);
///   - wpo[0] = getMinter(itBytes) -> mintCallback -> bytes(binding)
///     -> base64url = POT.
const String botGuardGlueScript = r'''
;(function(){
  var B = globalThis.__kmepBg = {
    phase: 'idle', err: null, response: null, degraded: false,
    wpoOk: false, pot: null, globalName: null, snapFn: null, wpoRef: null
  };

  function b64ToU8(s) {
    s = String(s).replace(/-/g, '+').replace(/_/g, '/').replace(/\./g, '=');
    var bin = atob(s), u = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
    return u;
  }
  function u8ToB64url(u) {
    var bin = '';
    for (var i = 0; i < u.length; i++) bin += String.fromCharCode(u[i]);
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_');
  }
  function noop() {}
  function fail(msg) { B.phase = 'error'; B.err = msg; }
  function setErr(prefix, e) { fail(prefix + ': ' + String((e && (e.message || e.stack)) || e)); }

  globalThis.__kmepBgStart = function(programJson, globalName) {
    try {
      B.globalName = String(globalName);
      var vm = globalThis[B.globalName];
      if (!vm || typeof vm.a !== 'function') {
        throw new Error('VM не найден после eval интерпретатора');
      }
      var asyncFns = [];
      B.phase = 'running';
      var ret = vm.a(String(programJson),
        function() {
          for (var i = 0; i < arguments.length; i++) asyncFns.push(arguments[i]);
        },
        true, undefined, noop, [[], []], undefined, false,
        [noop, noop, noop, noop, noop]);
      Promise.resolve(ret).then(function(arr) {
        if (arr && typeof arr[0] === 'function') {
          B.snapFn = arr[0];
          B.phase = 'ready';
        } else if (typeof asyncFns[0] === 'function') {
          B.snapFn = asyncFns[0];
          B.phase = 'ready';
        } else {
          fail('нет snapshot-функции (ret=' + Object.prototype.toString.call(arr) + ')');
        }
      }, function(e) { setErr('vm.a', e); });
      return 'ok';
    } catch (e) { setErr('start', e); }
    return 'err';
  };

  globalThis.__kmepBgSnapshot = function(binding) {
    try {
      if (!B.snapFn) throw new Error('фаза "' + B.phase + '", snapshot-функции нет');
      var wpo = [];
      B.phase = 'snapping';
      Promise.resolve(B.snapFn([undefined, undefined, wpo, undefined]))
        .then(function(response) {
          response = String(response);
          B.response = response;
          B.degraded = response.charAt(0) !== '$';
          B.wpoRef = wpo;
          B.wpoOk = wpo.length > 0 && typeof wpo[0] === 'function';
          B.phase = B.degraded ? 'degraded'
            : (B.wpoOk ? 'snapOk' : 'snapNoWpo');
        }, function(e) { setErr('snapshot', e); });
      return 'ok';
    } catch (e) { setErr('snapshot', e); }
    return 'err';
  };

  globalThis.__kmepBgMint = function(integrityTokenB64, binding) {
    try {
      if (!B.wpoRef || typeof B.wpoRef[0] !== 'function') {
        throw new Error('минтера нет (wpo пуст) — snapshot не выполнен или деградировал');
      }
      var getMinter = B.wpoRef[0];
      B.phase = 'minting';
      Promise.resolve(getMinter(b64ToU8(integrityTokenB64)))
        .then(function(mintCb) {
          if (typeof mintCb !== 'function') {
            throw new Error('APF:Failed — mintCallback не функция');
          }
          return Promise.resolve(
              mintCb(new TextEncoder().encode(String(binding))))
            .then(function(bytes) {
              if (!bytes) throw new Error('YNJ:Undefined');
              B.pot = u8ToB64url(bytes);
              B.phase = 'potOk';
            });
        })
        .catch(function(e) { setErr('mint', e); });
      return 'ok';
    } catch (e) { setErr('mint', e); }
    return 'err';
  };

  globalThis.__kmepBgState = function() {
    return JSON.stringify({
      phase: B.phase, err: B.err, degraded: B.degraded,
      wpoOk: B.wpoOk, response: B.response, pot: B.pot
    });
  };
})();
''';

/// Псевдоним для читаемости в bootstrap-сборке провайдера.
const String _glueScript = botGuardGlueScript;
