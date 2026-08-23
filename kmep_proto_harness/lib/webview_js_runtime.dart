import 'dart:async';
import 'dart:ui' show Size;
import 'dart:convert';

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
///
/// ОГРАНИЧЕНИЯ: evaluateJavascript асинхронный (мост через платформенный
/// канал) — каждый вызов ~1-5 мс оверхеда; большие скрипты передаются
/// строкой через канал без проблем (проверено 2.6 МБ).
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
    await headless.setSize(const Size(1280, 720));
    await headless.run();
    _headless = headless;
    _controller = headless.webViewController;
    await _ready.future.timeout(const Duration(seconds: 15));
    return _controller!;
  }

  /// Выполняет код как top-level statement'ы (indirect eval сохраняет
  /// глобальный скоуп — критично для var-деклараций player.js), ошибки
  /// возвращает значением {ok,err}.
  Future<Map<String, dynamic>> _runStatement(String code) async {
    final c = await _ensure();
    final src = '(function(){'
        'try{ (0,eval)(${jsonEncode(code)}); '
        'return JSON.stringify({ok:true}); }'
        'catch(e){ return JSON.stringify({ok:false, '
        'err:String(e&&(e.stack||e.message)||e)}); }'
        '})()';
    final raw = await c.evaluateJavascript(source: src);
    if (raw == null) {
      throw const KMEPException(
          KMEPErrorCode.nsigFail, 'WebView вернул null (JS упал до eval?)');
    }
    return jsonDecode(raw as String) as Map<String, dynamic>;
  }

  @override
  Future<void> bootstrap(String script) => bootstrapParts([script]);

  @override
  Future<void> bootstrapParts(List<String> parts) async {
    for (var i = 0; i < parts.length; i++) {
      final res = await _runStatement(parts[i]);
      if (res['ok'] != true) {
        throw KMEPException(
          KMEPErrorCode.nsigFail,
          'bootstrap player.js упал (часть ${i + 1}/${parts.length}): ${res['err']}',
        );
      }
    }
    // Санити: discovery обязан найти аплайер.
    final probe = await call(
        'String(globalThis.__kmepResolveFn ? "ok" : "missing")');
    if (probe == 'missing') {
      throw const KMEPException(
        KMEPErrorCode.nsigFail,
        'discovery не нашёл sig/nsig функцию в этом player.js',
      );
    }
  }

  @override
  Future<String> call(String expression) async {
    final c = await _ensure();
    final src = '(function(){'
        'try{ var r=(function(){${expression}})(); '
        'return JSON.stringify({ok:true,v:String(r===undefined?"":r)}); }'
        'catch(e){ return JSON.stringify({ok:false, '
        'err:String(e&&(e.stack||e.message)||e)}); }'
        '})()';
    final raw = await c.evaluateJavascript(source: src);
    if (raw == null) {
      throw const KMEPException(
          KMEPErrorCode.nsigFail, 'JS-вызов: WebView вернул null');
    }
    final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw KMEPException(
          KMEPErrorCode.nsigFail, 'JS-вызов упал: ${decoded['err']}');
    }
    return decoded['v'] as String? ?? '';
  }

  void dispose() {
    _disposed = true;
    _headless?.dispose();
    _headless = null;
    _controller = null;
  }
}
