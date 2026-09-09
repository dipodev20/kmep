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
/// ПОЧЕМУ ОН: форк QuickJS во flutter_js роняет компилятор на player.js
/// ("unconsistent stack size", pc=2895 — провал ss_check в
/// compute_stack_size, см. docs/AGENT_HANDOFF.md). В WebView свой полный
/// браузерный движок без этого ограничения, плюс НАСТОЯЩИЕ window/
/// document/navigator — browser_shim не нужен вовсе.
///
/// Origin: страница грузится через loadDataWithBaseURL с baseUrl
/// https://www.youtube.com/ — для player.js это родной origin.
class WebViewJsRuntime implements JsRuntime {
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;
  final Completer<void> _ready = Completer<void>();
  bool _disposed = false;

  /// [baseUrl] задаёт origin страницы-носителя скриптов.
  final Uri baseUrl;

  WebViewJsRuntime({Uri? baseUrl})
      : baseUrl = baseUrl ?? Uri.parse('https://www.youtube.com/');

  Future<InAppWebViewController> _ensure() async {
    if (_controller != null) return _controller!;
    if (_disposed) {
      throw const KMEPException(
          KMEPErrorCode.nsigFail, 'WebViewJsRuntime уже освобождён');
    }
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
        if (!_ready.isCompleted) _ready.complete();
      },
      onConsoleMessage: (_, __) {}, // глушим шум плеера
    );
    await headless.run();
    _headless = headless;
    _controller = headless.webViewController;
    await _ready.future.timeout(const Duration(seconds: 15));
    return _controller!;
  }

  /// Голый мост evaluateJavascript + текстовое представление сырого ответа
  /// (repr). repr идёт во все сообщения об ошибках — по нему видно, ЧТО
  /// именно вернул бридж (null / пустая строка / двойное JSON-кодирование
  /// / нормальный JSON), не гадая по пустым значениям.
  Future<(dynamic, String)> _evalRaw(String src) async {
    final c = await _ensure();
    final raw = await c.evaluateJavascript(source: src);
    final String repr;
    if (raw == null) {
      repr = 'null';
    } else if (raw is String) {
      repr = raw.isEmpty
          ? '<пустая строка>'
          : 'String(${raw.length}): "${_clip(raw)}"';
    } else {
      repr = '${raw.runtimeType}: ${_clip('$raw')}';
    }
    return (raw, repr);
  }

  /// Выполняет код как top-level statement'ы (indirect eval сохраняет
  /// глобальный скоуп — критично для var-деклараций player.js), ошибки
  /// возвращает значением {ok,err}.
  Future<Map<String, dynamic>> _runStatement(String code) async {
    final src = '(function(){'
        'try{ (0,eval)(${jsonEncode(code)}); '
        'return JSON.stringify({ok:true}); }'
        'catch(e){ return JSON.stringify({ok:false, '
        'err:String(e&&(e.stack||e.message)||e)}); }'
        '})()';
    final (raw, repr) = await _evalRaw(src);
    final decoded = _decodeResult(raw, 'JS-statement', repr);
    if (decoded['ok'] != true) {
      throw KMEPException(KMEPErrorCode.nsigFail,
          'bootstrap-часть упала: ${decoded['err']}');
    }
    return decoded;
  }

  @override
  Future<void> bootstrap(String script) => bootstrapParts([script]);

  @override
  Future<void> bootstrapParts(List<String> parts) async {
    for (var i = 0; i < parts.length; i++) {
      await _runStatement(parts[i]);
    }
    // Санити: различаем «бридж не отвечает» от «discovery не нашёл fn».
    // Раньше здесь сравнивали строку с 'missing' — мусорный ответ бридга
    // ('') проходил как ложный PASS. Теперь проверяем структуру и падаем
    // с точным диагнозом.
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
  }

  /// Снимок состояния JS-контекста одним выражением: эхо бридга, origin,
  /// целостность встроек (String/JSON могли быть затёрты top-level var из
  /// player.js через indirect eval), размер __closureFns, найденная fn.
  /// Бросает с repr сырого ответа, если бридж аномальный.
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
    final (raw, repr) = await _evalRaw(src);
    final decoded = _decodeResult(raw, 'envSnapshot', repr);
    if (decoded.containsKey('err')) {
      throw KMEPException(
          KMEPErrorCode.nsigFail, 'envSnapshot упал: ${decoded['err']}');
    }
    // echo !== '42' означает: выражение выполнилось, но вернулось НЕ то,
    // что посчитали внутри WebView — мост искажает результат.
    // (v12 падал здесь по ошибке диагностики: ждали '7' от String(6*7).)
    if (decoded['echo'] != '42') {
      throw KMEPException(
        KMEPErrorCode.nsigFail,
        'мост искажает результаты (echo=${decoded['echo']} вместо 42); '
            'сырой ответ: $repr',
      );
    }
    return decoded;
  }

  /// Мост evaluateJavascript возвращает ЛИБО сырую строку (тогда это JSON
  /// от JSON.stringify), ЛИБО уже распарсенный Map (платформа декодирует
  /// сама) — принимаем обе формы, аномалии показываем текстом.
  Map<String, dynamic> _decodeResult(dynamic raw, String what, String repr) {
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

  @override
  Future<String> call(String expression) async {
    // Плоская обёртка: выражение подставляется КАК ЕСТЬ в var r=(...),
    // без дополнительной вложенной IIFE вокруг него. Вложенная форма
    // (v11-v13) давала на устройстве r=undefined без исключения даже для
    // кода с безусловным return — подозрение на обработку глубокой
    // вложенности скобок в evaluateJavascript.
    final src = '(function(){'
        'try{ var r=(${expression}); '
        'return JSON.stringify({ok:true,'
        'v:String(r===undefined?"":r),'
        't:r===null?"null":typeof r}); }'
        'catch(e){ return JSON.stringify({ok:false, '
        'err:String(e&&(e.stack||e.message)||e)}); }'
        '})()';
    final (raw, repr) = await _evalRaw(src);
    final decoded = _decodeResult(raw, 'JS-вызов', repr);
    if (decoded['ok'] != true) {
      throw KMEPException(
          KMEPErrorCode.nsigFail, 'JS-вызов упал: ${decoded['err']}');
    }
    final v = decoded['v'] as String? ?? '';
    // Пустая строка — аномалия (в v11-v13 такие ответы молча маскировали
    // поломку). Читаем назад globalThis-переменную, которую выражение
    // должно было присвоить (__kmepOut/__kmepProbe/__kmepMarker): если она
    // УСТАНОВЛЕНА — присваивание внутри WebView произошло, а сломан именно
    // путь возврата значения.
    if (v.isEmpty) {
      String assigned;
      try {
        assigned =
            await call('String(JSON.stringify(globalThis.__kmepOut||null))');
      } catch (_) {
        assigned = '<readback упал>';
      }
      throw KMEPException(
        KMEPErrorCode.nsigFail,
        'JS-вызов вернул пустую строку (typeof=${decoded['t']}); '
            '__kmepOut=$assigned; сырой ответ моста: $repr',
      );
    }
    return v;
  }

  void dispose() {
    _disposed = true;
    _headless?.dispose();
    _headless = null;
    _controller = null;
  }
}

String _clip(String s, [int n = 200]) =>
    s.length > n ? '${s.substring(0, n)}...' : s;
