import 'package:flutter_js/flutter_js.dart';
import 'package:kmep_proto/kmep.dart' show JsRuntime;

// Этот файл живёт в flutter_integration/, а не в lib/src/resolvers/,
// потому что требует Flutter SDK (flutter_js) — подключается на шаге
// интеграции kmep-proto в само приложение Vidora, где Flutter уже есть.

/// Реализация [JsRuntime] поверх flutter_js: QuickJS на Android, JavaScriptCore
/// на iOS/macOS через тот же плагин.
class FlutterJsRuntime implements JsRuntime {
  JavascriptRuntime? _engine;
  bool _bootstrapped = false;

  JavascriptRuntime _ensureEngine() {
    return _engine ??= getJavascriptRuntime();
  }

  @override
  Future<void> bootstrap(String script) async {
    final engine = _ensureEngine();
    final result = await engine.evaluateAsync(script);
    if (result.isError) {
      throw JsEvaluationException(result.stringResult, script: '<bootstrap, ${script.length} chars>');
    }
    _bootstrapped = true;
  }

  @override
  Future<String> call(String expression) async {
    if (!_bootstrapped) {
      throw StateError('FlutterJsRuntime.call() до bootstrap() — сначала выполни player.js');
    }
    final engine = _ensureEngine();
    final wrapped = '(function(){ return String($expression); })()';
    final result = await engine.evaluateAsync(wrapped);
    if (result.isError) {
      throw JsEvaluationException(result.stringResult, script: expression);
    }
    return result.stringResult;
  }

  void dispose() {
    _engine?.dispose();
    _engine = null;
    _bootstrapped = false;
  }
}

class JsEvaluationException implements Exception {
  final String message;
  final String script;
  const JsEvaluationException(this.message, {required this.script});

  @override
  String toString() =>
      'JsEvaluationException: $message\n--- script (first 300 chars) ---\n'
      '${script.length > 300 ? script.substring(0, 300) : script}';
}
