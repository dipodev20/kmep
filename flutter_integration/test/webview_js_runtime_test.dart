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

import 'package:flutter_test/flutter_test.dart';
import '../webview_js_runtime.dart';
import 'package:kmep_proto/kmep.dart';

/// Фейковый мост evaluateJavascript: возвращает заготовленные ответы по
/// очереди (String ИЛИ уже распарсенный Map — мост flutter_inappwebview
/// сам декодирует JSON один раз) и записывает все исходники. Проверяем
/// ЛОГИКУ WebViewJsRuntime (плоская обёртка, декод обеих форм, структурное
/// санити discovery), не сам WebView.
class FakeBridge {
  final List<Object?> results = [];
  final List<String> sources = [];

  Future<Object?> eval(String src) {
    sources.add(src);
    if (results.isEmpty) throw StateError('no canned results');
    return Future.value(results.removeAt(0));
  }
}

const envOkJson =
    '{"echo":"42","href":"https://www.youtube.com/","origin":'
    '"https://www.youtube.com","strOk":true,"jsonOk":true,"doc":"object",'
    '"winSame":true,"fns":4090,"fn":"function","fnName":"ji"}';

WebViewJsRuntime runtimeWith(FakeBridge b) =>
    WebViewJsRuntime(evaluate: b.eval);

void main() {
  test('bootstrap ok -> санити по структуре -> call возвращает значение',
      () async {
    final b = FakeBridge();
    b.results.addAll([
      '{"ok":true}', // bootstrap-часть
      envOkJson, // envSnapshot-санити
      '{"ok":true,"v":"RESOLVED_URL","t":"String"}', // вызов
    ]);
    final rt = runtimeWith(b);

    await rt.bootstrapParts(['PREPARED_PLAYER+DISCOVERY']);
    final out = await rt.call('RESOLVE_EXPR');

    expect(out, 'RESOLVED_URL');
    // Вызов обёрнут ПЛОСКО: выражение подставлено как есть, без вложенной
    // IIFE (грабля Android: вложенная форма молча давала undefined).
    expect(b.sources.last, contains('var r=(RESOLVE_EXPR);'));
    expect(b.sources.last.contains('(function(){RESOLVE_EXPR'), isFalse);
    // bootstrap-часть ушла через indirect eval с jsonEncode.
    expect(b.sources.first, contains('(0,eval)'));
    expect(b.sources.first, contains('"PREPARED_PLAYER+DISCOVERY"'));
  });

  test('мост вернул уже распарсенный Map — принимаем', () async {
    final b = FakeBridge();
    b.results.addAll([
      {'ok': true}, // bootstrap-часть (Map-форма)
      envOkJson,
      '{"ok":true,"v":"X","t":"String"}',
    ]);
    final rt = runtimeWith(b);

    await rt.bootstrapParts(['P']);
    expect(await rt.call('E'), 'X');
  });

  test('bootstrap: коллектор пуст (fns=0) -> диагноз «коллектор»', () async {
    final b = FakeBridge();
    b.results.addAll([
      '{"ok":true}',
      envOkJson.replaceFirst('"fns":4090', '"fns":0')
          .replaceFirst('"fn":"function"', '"fn":"undefined"')
          .replaceFirst('"fnName":"ji"', '"fnName":""'),
    ]);
    final rt = runtimeWith(b);

    await expectLater(
      rt.bootstrapParts(['P']),
      throwsA(isA<KMEPException>()
          .having((e) => e.message, 'message', contains('коллектор'))),
    );
  });

  test(
      'bootstrap: функции есть, кандидат не выбран -> диагноз «discovery»',
      () async {
    final b = FakeBridge();
    b.results.addAll([
      '{"ok":true}',
      envOkJson.replaceFirst('"fn":"function"', '"fn":"null"')
          .replaceFirst('"fnName":"ji"', '"fnName":""'),
    ]);
    final rt = runtimeWith(b);

    await expectLater(
      rt.bootstrapParts(['P']),
      throwsA(isA<KMEPException>().having(
          (e) => e.message, 'message', contains('не выбрал кандидата'))),
    );
  });

  test('call до bootstrap запрещён', () async {
    final b = FakeBridge()..results.add('{"ok":true,"v":"Y","t":"String"}');
    final rt = runtimeWith(b);
    await expectLater(rt.call('X'), throwsA(isA<KMEPException>()));
    expect(b.sources, isEmpty);
  });

  test('JS-ошибка внутри выражения -> KMEPException с текстом ошибки',
      () async {
    final b = FakeBridge();
    b.results.addAll([
      '{"ok":true}',
      envOkJson,
      '{"ok":false,"err":"TypeError: ji is not a function"}',
    ]);
    final rt = runtimeWith(b);
    await rt.bootstrapParts(['P']);

    await expectLater(
      rt.call('BAD'),
      throwsA(isA<KMEPException>()
          .having((e) => e.message, 'message', contains('ji is not a'))),
    );
  });

  test('пустой результат (typeof=undefined) -> громкое исключение', () async {
    final b = FakeBridge();
    b.results.addAll([
      '{"ok":true}',
      envOkJson,
      '{"ok":true,"v":"","t":"undefined"}',
    ]);
    final rt = runtimeWith(b);
    await rt.bootstrapParts(['P']);

    await expectLater(
      rt.call('SILENTLY_BROKEN'),
      throwsA(isA<KMEPException>()
          .having((e) => e.message, 'message', contains('пустую строку'))),
    );
  });

  test('мост вернул мусор (не JSON) -> исключение с repr сырого ответа',
      () async {
    final b = FakeBridge()..results.add('garbage-not-json');
    final rt = runtimeWith(b);
    await expectLater(
      rt.bootstrapParts(['P']),
      throwsA(isA<KMEPException>()
          .having((e) => e.message, 'message', contains('garbage'))),
    );
  });

  test('dispose -> дальнейшие вызовы запрещены', () async {
    final b = FakeBridge();
    final rt = runtimeWith(b);
    rt.dispose();
    await expectLater(
      rt.bootstrapParts(['P']),
      throwsA(isA<KMEPException>()),
    );
  });
}
