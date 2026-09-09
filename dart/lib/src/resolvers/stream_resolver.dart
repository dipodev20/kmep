// KMEP — a from-scratch YouTube extraction library for Dart.
// Copyright (C) 2026 dipodev20
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert' show jsonEncode;

import '../models/kmep_models.dart';

/// Абстракция над JS-рантаймом (flutter_js / Deno / JavascriptCore-bridge).
///
/// ИСТОРИЯ РЕШЕНИЯ (важно для будущего чтения): изначально резолвер
/// вычленял ОДНУ функцию расшифровки regex'ом и выполнял только её. Не
/// сработало — современный player.js обфусцирует строковые литералы через
/// общую таблицу с XOR-обфусцированными индексами (`m[h^8856]` и т.п.),
/// так что вырезанная функция без остального файла не может разрешить свои
/// зависимости. Поэтому теперь схема другая:
///   1) один раз на player.js: bootstrap() — выполняет browser-shim
///      (заглушки под window/document/navigator и т.д., которых нет в
///      чистом JS-движке) + сам player.js целиком, в общем контексте.
///   2) дальше на каждый формат: call() — вызывает уже готовую публичную
///      функцию (например через _yt_player.XXX(...)) без повторной загрузки
///      2.5 МБ файла.
/// Это тяжелее в реализации, чем "вырезать одну функцию", но не ломается
/// от переименования внутренних хелперов — потому что мы не пытаемся сами
/// их понять, мы выполняем реальный код так же, как это делает браузer.
abstract class JsRuntime {
  Future<void> bootstrap(String script);
  Future<String> call(String expression);

  /// Bootstrap из НЕСКОЛЬКИХ отдельных evaluate-вызовов вместо одной
  /// склейки. Мост flutter_js на Android не переваривает одиночный
  /// исходник >~2.6 МБ ("InternalError: unconsistent stack size", поймано
  /// на устройстве), хотя те же куски по отдельности выполняются — поэтому
  /// прод-пайплайн шлёт шим/player.js/discovery раздельно.
  Future<void> bootstrapParts(List<String> parts);
}

/// Заглушки под браузерные глобалы, которых нет в голом JS-движке.
/// НЕ претендует на полноту — задача не эмулировать браузер целиком, а
/// дать player.js достаточно, чтобы дойти до конца top-level выполнения
/// не бросив исключение.
///
/// НАЙДЕННЫЕ И ПОЧИНЕННЫЕ ПРОБЛЕМЫ (через tool/find_nsig.js):
/// - document.referrer НЕ должен быть пустой строкой — где-то в коде
///   `new URL(document.referrer)`, на "" это бросает исключение.
/// - player.js делает `var window=this` внутри strict-mode функции,
///   вызванной обычным вызовом — this уходит в fallback без .location.
///   Патчится в _ensureBootstrapped() ЗАМЕНОЙ ТЕКСТА перед выполнением
///   (см. ниже), а не через сам шим.
const String browserShimScript = r'''
(function() {
  function noop() {}
  function Stub() {}
  Stub.prototype.addEventListener = noop;
  Stub.prototype.removeEventListener = noop;
  Stub.prototype.setAttribute = noop;
  Stub.prototype.getAttribute = function() { return null; };
  Stub.prototype.appendChild = function(x) { return x; };
  Stub.prototype.style = {};

  var storageBacking = {};
  var storage = {
    getItem: function(k) { return Object.prototype.hasOwnProperty.call(storageBacking, k) ? storageBacking[k] : null; },
    setItem: function(k, v) { storageBacking[k] = String(v); },
    removeItem: function(k) { delete storageBacking[k]; },
  };

  // Найдено через tool/find_nsig.js (player.js:6424):
  // window.location.hostname.split(".") на top-level — location должен
  // быть полноценным объектом, а не только { href }.
  var loc = {
    href: 'https://www.youtube.com/',
    protocol: 'https:',
    host: 'www.youtube.com',
    hostname: 'www.youtube.com',
    port: '',
    pathname: '/',
    search: '',
    hash: '',
    origin: 'https://www.youtube.com',
    toString: function() { return this.href; },
  };

  var doc = {
    createElement: function() { return new Stub(); },
    querySelector: function() { return null; },
    querySelectorAll: function() { return []; },
    getElementsByTagName: function() { return []; },
    getElementById: function() { return null; },
    documentElement: new Stub(),
    body: new Stub(),
    addEventListener: noop,
    removeEventListener: noop,
    location: loc,
    referrer: 'https://www.youtube.com/',
    compatMode: 'CSS1Compat',
  };

  var nav = {
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
    userAgentData: null,
    platform: 'Win32',
    language: 'en-US',
  };

  var safeSetTimeout = (typeof setTimeout !== 'undefined')
    ? setTimeout
    : function(fn) { fn(); return 0; };
  var safeClearTimeout = (typeof clearTimeout !== 'undefined') ? clearTimeout : function() {};

  var win = {
    document: doc,
    navigator: nav,
    location: doc.location,
    sessionStorage: storage,
    localStorage: storage,
    setTimeout: safeSetTimeout,
    clearTimeout: safeClearTimeout,
    setInterval: function() { return 0; },
    clearInterval: noop,
    performance: { now: function() { return Date.now(); }, timing: { navigationStart: Date.now() } },
    addEventListener: noop,
    removeEventListener: noop,
    innerWidth: 1280,
    innerHeight: 720,
    screen: { width: 1280, height: 720 },
  };
  win.window = win;
  win.self = win;
  win.top = win;
  win.parent = win;

  globalThis.window = win;
  globalThis.self = win;
  globalThis.document = doc;
  globalThis.navigator = nav;
  globalThis.sessionStorage = storage;
  globalThis.localStorage = storage;
  if (typeof globalThis.setTimeout === 'undefined') globalThis.setTimeout = safeSetTimeout;
  if (typeof globalThis.clearTimeout === 'undefined') globalThis.clearTimeout = safeClearTimeout;

  globalThis.MutationObserver = function() { this.observe = noop; this.disconnect = noop; this.takeRecords = function() { return []; }; };
  globalThis.ResizeObserver = globalThis.MutationObserver;
  globalThis.IntersectionObserver = function() { this.observe = noop; this.unobserve = noop; this.disconnect = noop; };
  globalThis.Worker = function() { throw new Error('Worker not supported in kmep-proto shim'); };

  // Найдено через tool/find_nsig.js (player.js:2206):
  // FI0() на top-level делает XMLHttpRequest.prototype.fetch — нужен
  // конструктор с прототипом (фича-детект вернёт false, этого достаточно).
  globalThis.XMLHttpRequest = function() {
    this.readyState = 0;
    this.status = 0;
    this.responseText = '';
    this.response = '';
  };
  globalThis.XMLHttpRequest.prototype.open = noop;
  globalThis.XMLHttpRequest.prototype.send = noop;
  globalThis.XMLHttpRequest.prototype.abort = noop;
  globalThis.XMLHttpRequest.prototype.setRequestHeader = noop;
  globalThis.XMLHttpRequest.prototype.getAllResponseHeaders = function() { return ''; };
  globalThis.XMLHttpRequest.prototype.getResponseHeader = function() { return null; };
  globalThis.XMLHttpRequest.prototype.addEventListener = noop;
  globalThis.XMLHttpRequest.prototype.removeEventListener = noop;

  if (typeof TextEncoder === 'undefined') {
    globalThis.TextEncoder = function() {};
    globalThis.TextEncoder.prototype.encode = function(s) {
      var bytes = [];
      for (var i = 0; i < s.length; i++) bytes.push(s.charCodeAt(i) & 0xff);
      return new Uint8Array(bytes);
    };
  }
})();
''';

/// Полная подготовка сырого player.js к bootstrap: патч window=this +
/// инжект коллектора выгрузки замыкания. Публичная — используется и
/// StreamResolver'ом, и on-device харнесом (kmep_proto_harness), чтобы
/// пайплайн не расходился между продом и диагностикой.
String preparePlayerJs(String rawPlayerJs) {
  var playerJs = rawPlayerJs.replaceAll(
      RegExp(r'\bwindow=this\b'), 'window=globalThis.window');
  return _injectClosureExport(playerJs);
}

/// Полный вход для JsRuntime.bootstrap: шим + подготовленный player.js +
/// discovery-скрипт. Единая точка сборки (прод == харнес).
String buildBootstrapScript(String rawPlayerJs) =>
    '$browserShimScript\n${preparePlayerJs(rawPlayerJs)}\n$discoverResolveFnScript';

class PlayerJsCacheEntry {
  final String jsUrl;
  final DateTime bootstrappedAt;
  PlayerJsCacheEntry({required this.jsUrl, required this.bootstrappedAt});
  bool isExpired(Duration ttl) =>
      DateTime.now().difference(bootstrappedAt) > ttl;
}

/// Экспорт функций из замыкания IIFE player.js.
///
/// Весь player.js — одна IIFE `(function(g){...})(_yt_player)`, все рабочие
/// функции (включая sig/nsig-аплайер) — локалы этого скоупа и снаружи
/// невидимы. Инжект перед закрывающей скобкой коллектора выгружает все
/// достижимые по имени функции в globalThis.__closureFns через eval,
/// который видит локальный скоуп. Собираем имена трёх видов:
///   NAME = function / NAME = class (top-level присваивания внутри IIFE)
///   function NAME(...) (декларации)
/// Тот же набор регэкспов, что в tool/probe_nsig_pipeline.js и
/// tool/find_nsig.js — держим синхронно.
const String _closureTailPattern = r'\}\)\(_yt_player\);\s*$';

String _injectClosureExport(String playerJs) {
  if (!RegExp(_closureTailPattern).hasMatch(playerJs)) {
    throw const KMEPException(
      KMEPErrorCode.nsigFail,
      'player.js: не найден хвост })(_yt_player); — структура файла изменилась',
    );
  }
  final names = <String>{
    for (final m in RegExp(
            r'(?:^|[,;\n}])([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?(?:function\b|class\b)')
        .allMatches(playerJs))
      m.group(1)!,
    for (final m in RegExp(r'(?:^|[;\n}])function\s+([A-Za-z_$][\w$]*)\s*\(')
        .allMatches(playerJs))
      m.group(1)!,
  };
  final nameList = names.map(jsonEncode).join(',');
  final collector = ';(function(){var o={};var names=[$nameList];'
      'for(var i=0;i<names.length;i++){try{var v=eval(names[i]);'
      'if(typeof v==="function")o[names[i]]=v}catch(e){}}'
      'globalThis.__closureFns=o;})();';
  return playerJs.replaceFirst(
      RegExp(_closureTailPattern), '$collector\n})(_yt_player);');
}

/// Поиск sig/nsig-аплайера среди выгруженных функций замыкания.
///
/// КАК РАБОТАЕТ (проверено 2026-08-22 на живом player.js, см.
/// tool/probe_nsig_pipeline.js): в этой сборке нет отдельной функции
/// "n-строка -> n-строка" — трансформация встроена в функции, работающие
/// с ЦЕЛЫМ URL через внутреннюю обёртку g.iO. Их маркер — вызов
/// X.Y("alr","yes") в теле (guard "already rewritten"). Найдена ji:
///   ji(url, sigParamName, rawSig) -> g.iO, где .KW() лениво сериализует
///   URL с дешифрованной подписью под sigParamName и трансформированным n.
/// Подход yt-dlp (ejs-солвер) использует тот же маркер.
///
/// Имена между релизами player.js меняются, поэтому ищем ПОВЕДЕНЧЕСКИ:
/// перебираем функции с маркером, дёргаем каждую с dummy googlevideo-URL
/// и берём первую, которая (а) вернула объект с .KW(), (б) дала строку
/// с alr=yes, (в) реально меняет n. Предпочтение тем, кто создаёт g.iO.
const String discoverResolveFnScript = r'''
;(function(){
  var fns = globalThis.__closureFns || {};
  var dummy = 'https://rr1---sn-nx57ynsk.googlevideo.com/videoplayback?expire=1799999999&n=ABCDEFGHIJKLMNOP&ratebypass=yes';
  var preferred = [], others = [];
  for (var k in fns) {
    var src;
    try { src = Function.prototype.toString.call(fns[k]); } catch (e) { continue; }
    if (src.indexOf('"alr"') === -1 || src.indexOf('"yes"') === -1) continue;
    (src.indexOf('new g.iO(') !== -1 ? preferred : others).push([k, fns[k]]);
  }
  globalThis.__kmepResolveFn = null;
  globalThis.__kmepResolveFnName = null;
  var pool = preferred.concat(others);
  for (var i = 0; i < pool.length; i++) {
    try {
      var obj = pool[i][1](dummy, '', '');
      if (!obj || typeof obj.KW !== 'function') continue;
      var out = String(obj.KW());
      if (out.indexOf('alr=yes') === -1) continue;
      if (out.indexOf('n=ABCDEFGHIJKLMNOP') !== -1) continue;
      globalThis.__kmepResolveFn = pool[i][1];
      globalThis.__kmepResolveFnName = pool[i][0];
      break;
    } catch (e) {}
  }
})();
''';

/// Выражение для одного вызова аплайера: полный URL (+ параметры
/// signatureCipher, если формат зашифрован) -> готовый URL строкой.
///
/// ВАЖНО: вызывать ровно ОДИН раз на URL — повторный прогон уже
/// обработанного URL трансформирует n ещё раз и делает ссылку невалидной.
String _defaultResolveUrlExpression(
    String url, String? sigParam, String? signature) {
  final sp = jsonEncode(sigParam ?? '');
  final s = jsonEncode(signature ?? '');
  return 'globalThis.__kmepOut=(function(){'
      'var f=globalThis.__kmepResolveFn;'
      'if(!f||typeof f!=="function"){'
      'throw new Error("kmep: sig/nsig resolve function not discovered at bootstrap")}'
      'return String(f(${jsonEncode(url)},$sp,$s).KW())})()';
}

/// Резолвер потоков через полное выполнение player.js.
class StreamResolver {
  final JsRuntime jsRuntime;
  final Future<String> Function(String jsUrl) fetchPlayerJs;
  final Duration cacheTtl;

  /// Переопределение выражения вызова аплайера. По умолчанию — вызов
  /// найденной на bootstrap-этапе функции (см. _discoverResolveFnScript).
  final String Function(String url, String? sigParam, String? signature)
      buildResolveUrlExpression;

  String? _bootstrappedFor;

  StreamResolver({
    required this.jsRuntime,
    required this.fetchPlayerJs,
    this.cacheTtl = const Duration(hours: 24),
    this.buildResolveUrlExpression = _defaultResolveUrlExpression,
  });

  Future<List<KMEPStream>> resolve(
    List<Map<String, dynamic>> rawFormats, {
    required String playerJsUrl,
  }) async {
    await _ensureBootstrapped(playerJsUrl);
    final resolved = <KMEPStream>[];

    for (final fmt in rawFormats) {
      final mimeType = fmt['mimeType'] as String? ?? '';
      final isAudio = mimeType.startsWith('audio/');
      String? url = fmt['url'] as String?;
      final cipher =
          fmt['signatureCipher'] as String? ?? fmt['cipher'] as String?;
      String? sigParam;
      String? signature;

      if (url == null && cipher != null) {
        final params = Uri.splitQueryString(cipher);
        url = params['url'];
        sigParam = params['sp'] ?? 'sig';
        signature = params['s'];
      }
      if (url == null) continue;

      // Формат требует вызова player.js только если зашифрован или несёт n.
      final needsPlayerJs =
          signature != null || Uri.parse(url).queryParameters.containsKey('n');
      if (needsPlayerJs) {
        url = await _resolveUrlViaPlayerJs(url, sigParam, signature);
      }

      resolved.add(KMEPStream(
        url: url,
        quality:
            (fmt['qualityLabel'] as String?) ?? (isAudio ? 'audio' : 'unknown'),
        codec: _extractCodec(mimeType),
        type: isAudio ? 'audio' : 'video',
        itag: (fmt['itag'] as num?)?.toInt() ?? 0,
        width: (fmt['width'] as num?)?.toInt(),
        height: (fmt['height'] as num?)?.toInt(),
        bitrate: (fmt['bitrate'] as num?)?.toInt(),
        mimeType: mimeType,
      ));
    }

    if (resolved.isEmpty && rawFormats.isNotEmpty) {
      final sabrOnly = rawFormats
          .where((f) =>
              f['url'] == null &&
              f['signatureCipher'] == null &&
              f['cipher'] == null)
          .length;
      throw KMEPException(
        KMEPErrorCode.nsigFail,
        sabrOnly == rawFormats.length
            ? 'Все ${rawFormats.length} форматов — SABR-дескрипторы без URL '
                '(serverAbrStreamingUrl); прямой экстракции нет'
            : 'Failed to resolve any stream URL',
      );
    }
    return resolved;
  }

  Future<void> _ensureBootstrapped(String jsUrl) async {
    if (_bootstrappedFor == jsUrl) {
      return; // тот же player.js — не грузим повторно
    }
    final playerJs = await fetchPlayerJs(jsUrl);
    // Патч window=this + коллектор замыкания — внутри preparePlayerJs
    // (найдено экспериментально, см. комментарии там). Части шлём
    // РАЗДЕЛЬНО: склейка в один evaluate ломает мост flutter_js.
    await jsRuntime.bootstrapParts([
      browserShimScript,
      preparePlayerJs(playerJs),
      discoverResolveFnScript,
    ]);
    _bootstrappedFor = jsUrl;
  }

  Future<String> _resolveUrlViaPlayerJs(
      String url, String? sigParam, String? signature) async {
    final expression = buildResolveUrlExpression(url, sigParam, signature);
    late final String resolved;
    try {
      resolved = await jsRuntime.call(expression);
    } on KMEPException {
      rethrow;
    } catch (e) {
      throw KMEPException(
        KMEPErrorCode.nsigFail,
        'player.js sig/nsig call failed: $e',
      );
    }
    final trimmed = resolved.trim();
    if (trimmed.isEmpty ||
        !(trimmed.startsWith('http://') || trimmed.startsWith('https://'))) {
      throw const KMEPException(
        KMEPErrorCode.nsigFail,
        'player.js sig/nsig call вернул не URL',
      );
    }
    return trimmed;
  }

  String _extractCodec(String mimeType) {
    final match = RegExp('codecs="([^"]+)"').firstMatch(mimeType);
    return match?.group(1) ?? 'unknown';
  }
}
