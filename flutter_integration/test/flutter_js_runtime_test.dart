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

import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import '../flutter_js_runtime.dart';
import 'package:kmep_proto/kmep.dart';

/// Фейковый JavascriptRuntime: возвращает заготовленные результаты по
/// очереди и записывает все исходники evaluate — проверяем ЛОГИКУ
/// FlutterJsRuntime (маркер ошибок, санити discovery, порядок вызовов),
/// не сам движок.
class FakeJavascriptRuntime implements JavascriptRuntime {
  final List<JsEvalResult> results = [];
  final List<String> evaluated = [];

  @override
  JsEvalResult evaluate(String code, {String? sourceUrl}) {
    evaluated.add(code);
    if (results.isEmpty) throw StateError('no canned results');
    return results.removeAt(0);
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('bootstrap ok + санити discovery ok -> call возвращает значение',
      () async {
    final js = FakeJavascriptRuntime();
    js.results.addAll([
      JsEvalResult('undefined', null), // bootstrap: весь скрипт
      JsEvalResult('ok', null), // санити __kmepResolveFn
      JsEvalResult('RESOLVED_URL', null), // вызов выражения
    ]);
    final runtime = FlutterJsRuntime(engine: js);

    await runtime.bootstrap('SHIM+PLAYER+DISCOVERY');
    final out = await runtime.call('SOME_EXPRESSION');

    expect(out, 'RESOLVED_URL');
    // Первый eval — весь bootstrap-скрипт целиком.
    expect(js.evaluated.first, contains('SHIM+PLAYER'));
    // Вызов обёрнут: выражение передано через eval(jsonEncode(...)).
    expect(js.evaluated.last, contains('"SOME_EXPRESSION"'));
    expect(js.evaluated.last, contains('__KMEP_ERR__'));
  });

  test('bootstrap с isError -> KMEPException', () async {
    final js = FakeJavascriptRuntime();
    js.results.add(JsEvalResult('ReferenceError: boom', null, isError: true));
    final runtime = FlutterJsRuntime(engine: js);

    await expectLater(
      runtime.bootstrap('BROKEN'),
      throwsA(isA<KMEPException>()
          .having((e) => e.code, 'code', KMEPErrorCode.nsigFail)),
    );
  });

  test('bootstrap: discovery не нашёл аплайер -> KMEPException сразу', () async {
    final js = FakeJavascriptRuntime();
    js.results.addAll([
      JsEvalResult('undefined', null),
      JsEvalResult('missing', null),
    ]);
    final runtime = FlutterJsRuntime(engine: js);

    await expectLater(
      runtime.bootstrap('PLAYER_WITHOUT_RESOLVE_FN'),
      throwsA(isA<KMEPException>()
          .having((e) => e.message, 'message', contains('discovery'))),
    );
  });

  test('call до bootstrap запрещён', () async {
    final runtime = FlutterJsRuntime(engine: FakeJavascriptRuntime());
    await expectLater(
      runtime.call('X'),
      throwsA(isA<KMEPException>()),
    );
  });

  test('JS-ошибка внутри вызова (маркер) -> KMEPException с сообщением',
      () async {
    final js = FakeJavascriptRuntime();
    js.results.addAll([
      JsEvalResult('undefined', null),
      JsEvalResult('ok', null),
      JsEvalResult('__KMEP_ERR__:ji is not defined', null),
    ]);
    final runtime = FlutterJsRuntime(engine: js);
    await runtime.bootstrap('OK_SCRIPT');

    await expectLater(
      runtime.call('BAD'),
      throwsA(isA<KMEPException>()
          .having((e) => e.message, 'message', contains('ji is not defined'))),
    );
  });
}
