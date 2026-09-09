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

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:kmep_proto/kmep.dart'
    show JsRuntime, KMEPException, KMEPErrorCode;

/// JsRuntime поверх headless WebView (системный движок: Chrome/V8 на
/// Android, WebKit на iOS).
///
/// ПОЧЕМУ ОН ВМЕСТО FlutterJsRuntime (QuickJS): форк QuickJS во flutter_js
/// НЕДЕТЕРМИНИРОВАННО роняет компилятор на player.js ("unconsistent stack
/// size", pc=2895; ретраи x5 не спасают). Системный движок этих ограничений
/// не имеет. ПРОВЕРЕНО НА УСТРОЙСТВЕ (харнес v14, 2026-08-23): n-тест
/// совпал с эталоном Node, origin youtube.com, fns=4090, fn=ji.
///
/// ГЛАВНАЯ ГРАБЛЯ (стоит дня отладки): обёртка вызова для
/// evaluateJavascript. Форма с вложенной IIFE вокруг выражения —
/// `(function(){try{ var r=(function(){EXPR})(); return ... })()` — НА
/// ANDROID МОЛЧА ВОЗВРАЩАЕТ r=undefined даже для кода с безусловным
/// return. РАБОЧАЯ форма — плоская подстановка: `var r=(EXPR);`.
/// Не оборачивать пользовательское выражение в дополнительную функцию.
///
/// Мост: flutter_inappwebview сам декодирует JSON ответа один раз, поэтому
/// сырой ответ приходит ЛИБО String (декодируем вторично), ЛИБО уже Map —
/// принимаем обе формы (_decodeResult); аномалии включают repr сырого
/// ответа в текст исключения.
class WebViewJsRuntime implements JsRuntime {
  /// Инъекция моста для тестов; null -> ленивый headless WebView
  /// ([_ensureBridge]). Резолвится в [_evalRaw] при первом вызове.
  Future<Object?> Function(String source)? _evaluate;

  HeadlessInAppWebView? _headless;
  bool _disposed = false;
  bool _bootstrapped = false;

  /// [baseUrl] задаёт origin страницы-носителя скриптов: для player.js это
  /// должен быть youtube.com (реферер/origin-гварды внутри плеера).
  final Uri baseUrl;

  WebViewJsRuntime({Uri? baseUrl, Future<Object?> Function(String)? evaluate})
      : _evaluate = evaluate,
        baseUrl = baseUrl ?? Uri.parse('https://www.youtube.com/');

  /// Создаёт headless WebView с origin [baseUrl] и возвращает мост.
  /// Свой Completer на каждый WebView: общий пропускал бы чужой onLoadStop
  /// при нескольких рантаймах в процессе.
  Future<Object?> Function(String) _ensureBridge() {
    final existing = _evaluate;
    if (existing != null) return existing;
    final ready = Completer<void>();
    final headless = HeadlessInAppWebView(
      initialSize: const Size(1280, 720),
      initialSettings: InAppWebViewSettings(
        // Никакого визуального мусора и лишней активности.
        javaScriptEnabled: true,
        transparentBackground: true,
        supportZoom: false,
        disableContextMenu: true,
      ),
      initialData: InAppWebViewInitialData(
        data: '<!doctype html><html><body></body></html>',
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri(baseUrl.toString()),
      ),
      onLoadStop: (_, __) {
        if (!ready.isCompleted) ready.complete();
      },
      onConsoleMessage: (_, __) {}, // глушим шум плеера
    );
    _headless = headless;
    late final Future<Object?> Function(String) bridge;
    bridge = (src) async {
      await headless.run();
      await ready.future.timeout(const Duration(seconds: 15));
      final raw = await headless.webViewController!
          .evaluateJavascript(source: src);
      return raw;
    };
    _evaluate = bridge;
    return bridge;
  }

  @override
  Future<void> bootstrap(String script) => bootstrapParts([script]);

  @override
  Future<void> bootstrapParts(List<String> parts) async {
    _ensureNotDisposed();
    for (final part in parts) {
      // Indirect eval сохраняет глобальный скоуп — критично для
      // var-деклараций player.js.
      final src = '(function(){'
          'try{ (0,eval)(${jsonEncode(part)}); '
          'return JSON.stringify({ok:true}); }'
          'catch(e){ return JSON.stringify({ok:false, '
          'err:String(e&&(e.stack||e.message)||e)}); }'
          '})()';
      final decoded = await _evalStructured(src, 'bootstrap-часть');
      if (decoded['ok'] != true) {
        throw KMEPException(
            KMEPErrorCode.nsigFail, 'bootstrap-часть упала: ${decoded['err']}');
      }
    }
    // Санити: различаем «бридж не отвечает» от «discovery не нашёл fn».
    // Сравнение строк с 'missing' здесь недопустимо: мусорный '' проходил
    // бы как ложный PASS (грабли v11).
    final env = await envSnapshot();
    if (env['fn'] != 'function') {
      final fns = env['fns'];
      final reason = fns == 0
          ? 'коллектор не выгрузил ни одной функции из IIFE '
              '(fns=0; href=${env['href']})'
          : 'функций выгружено $fns, но discovery не выбрал кандидата '
              '(нет маркера "alr"/"yes" или dummy-тест не прошёл)';
      throw KMEPException(
        KMEPErrorCode.nsigFail,
        'discovery не нашёл sig/nsig функцию в этом player.js: $reason',
      );
    }
    _bootstrapped = true;
  }

  /// Снимок состояния JS-контекста одним вызовом: эхо бридга (мост искажает
  /// ответы?), origin страницы, целостность встроек String/JSON (top-level
  /// var из player.js мог затереть их через indirect eval), размер
  /// __closureFns, найденная discovery функция. Бросает при аномалиях.
  Future<Map<String, dynamic>> envSnapshot() async {
    final src = '(function(){'
        'try{ return JSON.stringify({'
        'echo:String(6*7),'
        'href:String(location.href),'
        'origin:String(location.origin),'
        'strOk:String(123)==="123",'
        'jsonOk:(function(){try{return JSON.stringify({a:1})==="{\\"a\\":1}"}'
        'catch(e){return false}})(),'
        'doc:typeof document,'
        'winSame:Object.is(window,globalThis.window),'
        'fns:Object.keys(globalThis.__closureFns||{}).length,'
        'fn:typeof globalThis.__kmepResolveFn,'
        'fnName:String(globalThis.__kmepResolveFnName||"")'
        '}); }'
        'catch(e){ return JSON.stringify({ok:false, '
        'err:String(e&&(e.stack||e.message)||e)}); }'
        '})()';
    final decoded = await _evalStructured(src, 'envSnapshot');
    if (decoded.containsKey('err')) {
      throw KMEPException(
          KMEPErrorCode.nsigFail, 'envSnapshot упал: ${decoded['err']}');
    }
    if (decoded['echo'] != '42') {
      throw KMEPException(KMEPErrorCode.nsigFail,
          'мост искажает результаты (echo=${decoded['echo']} вместо 42)');
    }
    return decoded;
  }

  @override
  Future<String> call(String expression) async {
    if (!_bootstrapped) {
      throw const KMEPException(
          KMEPErrorCode.nsigFail, 'WebViewJsRuntime: bootstrap не вызван');
    }
    // Плоская обёртка: выражение подставляется КАК ЕСТЬ в var r=(...),
    // без вложенной IIFE (см. доку класса — грабля Android).
    final src = '(function(){'
        'try{ var r=(${expression}); '
        'return JSON.stringify({ok:true,'
        'v:String(r===undefined?"":r),'
        't:r===null?"null":typeof r}); }'
        'catch(e){ return JSON.stringify({ok:false, '
        'err:String(e&&(e.stack||e.message)||e)}); }'
        '})()';
    final decoded = await _evalStructured(src, 'JS-вызов');
    if (decoded['ok'] != true) {
      throw KMEPException(
          KMEPErrorCode.nsigFail, 'JS-вызов упал: ${decoded['err']}');
    }
    final v = decoded['v'] as String? ?? '';
    // Пустая строка — аномалия (undefined/тихий провал), резолвер так не
    // отвечает. Громко наверх с repr сырого ответа моста.
    if (v.isEmpty) {
      throw KMEPException(
        KMEPErrorCode.nsigFail,
        'JS-вызов вернул пустую строку (typeof=${decoded['t']})',
      );
    }
    return v;
  }

  /// Сырой мост + repr результата для сообщений об ошибках.
  Future<(dynamic, String)> _evalRaw(String src) async {
    _ensureNotDisposed();
    final raw = await (_evaluate ?? _ensureBridge())(src);
    final String repr;
    if (raw == null) {
      repr = 'null';
    } else if (raw is String) {
      repr =
          raw.isEmpty ? '<пустая строка>' : 'String(${raw.length}): "$raw"';
    } else {
      repr = '${raw.runtimeType}: $raw';
    }
    return (raw, repr);
  }

  /// _evalRaw + декод в Map + громкие ошибки с repr.
  Future<Map<String, dynamic>> _evalStructured(String src, String what) async {
    final (raw, repr) = await _evalRaw(src);
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        return jsonDecode(raw) as Map<String, dynamic>;
      } on FormatException catch (e) {
        throw KMEPException(KMEPErrorCode.nsigFail,
            '$what: бридж вернул не-JSON ($e), сырой ответ: $repr');
      }
    }
    throw KMEPException(
      KMEPErrorCode.nsigFail,
      '$what: неожиданный ответ моста (${raw.runtimeType}), сырой ответ: $repr',
    );
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const KMEPException(
          KMEPErrorCode.nsigFail, 'WebViewJsRuntime уже освобождён');
    }
  }

  /// Освобождает нативный WebView. После этого рантайм не пригоден.
  void dispose() {
    _disposed = true;
    _headless?.dispose();
    _headless = null;
  }
}
