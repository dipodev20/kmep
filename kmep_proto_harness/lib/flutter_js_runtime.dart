import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:kmep_proto/kmep.dart' show JsRuntime, KMEPException, KMEPErrorCode;

/// JsRuntime поверх flutter_js.
///
/// НАЗНАЧЕНИЕ: прод на мобильных (Android = QuickJS через ffi,
/// iOS = JavaScriptCore). Интерфейс тот же, что у NodeProcessJsRuntime
/// (десктоп-диагностика), поэтому весь пайплайн StreamResolver — shim +
/// патч window=this + коллектор замыкания + discovery + выражения вызова —
/// переиспользуется БЕЗ изменений.
///
/// ОТЛИЧИЯ от процессного рантайма:
/// - нет изоляции состояния между вызовами не нужно: движок живёт в
///   объекте, _yt_player/__closureFns/__kmepResolveFn сохраняются между
///   call() как и в Node-версии;
/// - НЕТ таймаута на вызов: зацикленный JS заблокирует платформенный
///   поток. Приложение должно вызывать резолвер из фонового isolate
///   (compute/Isolate.run), чтобы не морозить UI;
/// - bootstrap выполняет ~3 МБ исходника одним evaluate — это секунды,
///   делать один раз на релиз player.js (кэш резолвера это учитывает).
class FlutterJsRuntime implements JsRuntime {
  final JavascriptRuntime _js;
  bool _bootstrapped = false;

  /// Инъекция движка для тестов; в проде используется платформенный
  /// дефолт (QuickJS на Android, JavaScriptCore на iOS).
  ///
  /// [stackSize] пробрасывается в QuickJsRuntime2.stackSize
  /// (jsSetMaxStackSize). Дефолт пакета 1 МБ; для диагностики матрицы
  /// размеров можно переопределить. Применяется лениво до первого
  /// evaluate (_ensureEngine).
  FlutterJsRuntime({JavascriptRuntime? engine, int? stackSize})
      : _js = engine ?? _createDefault(stackSize);

  static JavascriptRuntime _createDefault(int? stackSize) {
    final rt = getJavascriptRuntime();
    if (rt is QuickJsRuntime2 && stackSize != null) {
      rt.stackSize = stackSize;
    }
    return rt;
  }

  /// Маркер ошибки внутри JS: перехватываем исключение там же и возвращаем
  /// обычную строку — так мы не зависим от того, как конкретный мост
  /// flutter_js форматирует брошенные исключения.
  static const _errMarker = '__KMEP_ERR__';

  @override
  Future<void> bootstrap(String script) async {
    await bootstrapParts([script]);
  }

  @override
  Future<void> bootstrapParts(List<String> parts) async {
    for (var i = 0; i < parts.length; i++) {
      // Мост flutter_js выполняет JS на отдельном потоке и его стековая
      // бухгалтерия НЕДЕТЕРМИНИРОВАННА: один и тот же исходник проходит
      // через раз ("unconsistent stack size", стабильно pc=2895 на
      // player.js). Ретраи решают: отказы независимы между прогонами
      // (стадия B3 проходила непосредственно перед падавшей частью).
      const maxAttempts = 5;
      Object? lastErr;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          final result = _js.evaluate(parts[i]);
          if (!result.isError) {
            lastErr = null;
            break;
          }
          lastErr = result.stringResult;
        } catch (e) {
          lastErr = e;
        }
        await Future<void>.delayed(Duration(milliseconds: 60 * attempt));
      }
      if (lastErr != null) {
        throw KMEPException(
          KMEPErrorCode.nsigFail,
          'bootstrap player.js упал (часть ${i + 1}/${parts.length}, '
          '$maxAttempts попыток): $lastErr',
        );
      }
    }
    // Санити: discovery обязан найти аплайер. Если нет — лучше узнать сейчас.
    final probe = _callRaw(
        'String(globalThis.__kmepResolveFn ? "ok" : "missing")');
    if (probe == 'missing') {
      throw const KMEPException(
        KMEPErrorCode.nsigFail,
        'discovery не нашёл sig/nsig функцию в этом player.js',
      );
    }
    _bootstrapped = true;
  }

  @override
  Future<String> call(String expression) async {
    if (!_bootstrapped) {
      throw const KMEPException(
          KMEPErrorCode.nsigFail, 'FlutterJsRuntime: bootstrap не вызван');
    }
    final out = _callRaw(expression);
    if (out.startsWith(_errMarker)) {
      throw KMEPException(KMEPErrorCode.nsigFail,
          'player.js вызов упал: ${out.substring(_errMarker.length)}');
    }
    return out;
  }

  /// Диагностика: сырой evaluate без маркерных обёрток. Ошибки движка
  /// пробрасываются нативным JSError как есть (нужно стадийным тестам).
  void evaluateRaw(String code) {
    _js.evaluate(code);
  }

  /// Исполняет выражение, превращая JS-исключения в строку с маркером.
  /// Оборачивание через eval(jsonEncode(...)) защищает от любых кавычек
  /// внутри выражений, собираемых из пользовательских данных.
  String _callRaw(String expression) {
    final src = '(function(){'
        'try{ return eval(${jsonEncode(expression)}); }'
        'catch(e){ return "$_errMarker:" + String(e && e.message || e); }'
        '})()';
    final result = _js.evaluate(src);
    if (result.isError) {
      throw KMEPException(
          KMEPErrorCode.nsigFail, 'JS engine error: ${result.stringResult}');
    }
    return result.stringResult;
  }
}
