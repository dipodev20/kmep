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

// Юнит-тесты BotGuardJsPoTokenProvider на фейковом JsRuntime:
// state machine провайдера, поллинг фаз, кэш сессии/биндингов,
// деградация (R3) и отказ GenerateIT (R2) -> null без исключений.

import 'dart:convert';

import 'package:test/test.dart';
import 'package:kmep/kmep.dart';

class FakeJsRuntime implements JsRuntime {
  final List<String> bootstrapped = [];
  final List<String> calls = [];

  // Сценарий:
  bool degradeSnapshot = false;
  bool dropWpo = false;
  bool failMint = false;

  Map<String, dynamic> _state = {'phase': 'idle'};

  @override
  Future<void> bootstrap(String script) => bootstrapParts([script]);

  @override
  Future<void> bootstrapParts(List<String> parts) async {
    bootstrapped.addAll(parts);
    _state = {'phase': 'idle'};
  }

  @override
  Future<String> call(String expression) async {
    calls.add(expression);
    if (expression.startsWith('__kmepBgStart(')) {
      _state = {'phase': 'ready'};
    } else if (expression.startsWith('__kmepBgSnapshot(')) {
      if (degradeSnapshot) {
        _state = {
          'phase': 'degraded',
          'response': 'deadbeef01',
          'degraded': true,
          'wpoOk': false,
        };
      } else {
        _state = {
          'phase': dropWpo ? 'snapNoWpo' : 'snapOk',
          'response': r'$BG-OK-RESPONSE',
          'degraded': false,
          'wpoOk': !dropWpo,
        };
      }
    } else if (expression.startsWith('__kmepBgMint(')) {
      if (failMint) {
        _state = {'phase': 'error', 'err': 'mint: APF:Failed'};
      } else {
        _state = {..._state, 'phase': 'potOk', 'pot': 'FAKE-POT-TOKEN'};
      }
    } else if (expression.startsWith('__kmepBgState()')) {
      // no-op: читаем текущее состояние
    } else {
      throw KMEPException(
          KMEPErrorCode.potFail, 'неожиданный вызов: $expression');
    }
    return jsonEncode(_state);
  }
}

const _homepageHtml = '''
<html><script>ytcfg.set({"VISITOR_DATA":"CgtWSURFT1BEQVRB","EVENT_ID":"abc"});</script>
<script>window.ytAtN({cfg:{a:1}, R:{bgChallenge:{
  program:'PROGRAM-CODE',
  globalName:'_ytBgVm',
  interpreterUrl:{privateDoNotAccessOrElseTrustedResourceUrlWrappedValue:'//www.google.com/js/th/testhash.js'}
}}});</script></html>
''';

void main() {
  late FakeJsRuntime js;
  late List<(Uri, String)> generateItCalls;

  BotGuardJsPoTokenProvider makeProvider({
    Map<String, String> Function()? bindings,
    String Function(Uri, String)? generateItResponder,
  }) =>
      BotGuardJsPoTokenProvider(
        jsRuntime: js,
        fetchText: (url) async {
          if (url.contains('google.com/js/th/')) return '//INTERPRETER//';
          return _homepageHtml;
        },
        postGenerateItOverride: (url, body) async {
          generateItCalls.add((url, body));
          final respond =
              generateItResponder ?? ((url, body) => '["IT-TOKEN",43200]');
          final out = respond(url, body);
          if (!out.startsWith('[')) {
            throw KMEPException(KMEPErrorCode.potFail, 'GenerateIT HTTP $out');
          }
          return out;
        },
        bindingResolver: bindings,
        stepTimeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 1),
      );

  setUp(() {
    js = FakeJsRuntime();
    generateItCalls = [];
  });

  test('happy path: челлендж->интерпретатор->snapshot->GenerateIT->минтинг',
      () async {
    final p = makeProvider();
    final pot = await p.tokenFor('dQw4w9WgXcQ');

    expect(pot, 'FAKE-POT-TOKEN');
    expect(p.lastError, isNull);

    // Bootstrap: glue + env (yt.config_, delete VM) + интерпретатор.
    expect(js.bootstrapped.length, 3);
    expect(js.bootstrapped[0], contains('__kmepBgStart'));
    expect(js.bootstrapped[1], contains('config_'));
    expect(js.bootstrapped[1], contains('_ytBgVm'));
    expect(js.bootstrapped[2], '//INTERPRETER//');

    // GenerateIT получил РОВНО наш snapshot-ответ и правильный ключ.
    expect(generateItCalls, hasLength(1));
    expect(generateItCalls.first.$1.toString(),
        contains('google.internal.waa.v1.Waa/GenerateIT'));
    final sent = jsonDecode(generateItCalls.first.$2) as List<dynamic>;
    expect(sent[0], BotGuardJsPoTokenProvider.requestKeyForTest);
    expect(sent[1], r'$BG-OK-RESPONSE');

    // Минтинг — с integrity token и биндингом videoId по умолчанию.
    final mintCall = js.calls.firstWhere((c) => c.startsWith('__kmepBgMint('));
    expect(mintCall, contains('IT-TOKEN'));
    expect(mintCall, contains('dQw4w9WgXcQ'));
  });

  test('кэш сессии: второй биндинг БЕЗ нового homepage/GenerateIT', () async {
    var fetchCount = 0;
    final p = BotGuardJsPoTokenProvider(
      jsRuntime: js,
      fetchText: (url) async {
        if (url.contains('google.com/js/th/')) return '//I//';
        fetchCount++;
        return _homepageHtml;
      },
      postGenerateItOverride: (url, body) async {
        generateItCalls.add((url, body));
        return '["IT-TOKEN",43200]';
      },
      stepTimeout: const Duration(seconds: 2),
      pollInterval: const Duration(milliseconds: 1),
    );

    expect(await p.tokenFor('video1'), 'FAKE-POT-TOKEN');
    expect(await p.tokenFor('video2'), 'FAKE-POT-TOKEN');
    expect(fetchCount, 1); // homepage один раз
    expect(generateItCalls, hasLength(1)); // integrity token из кэша
    expect(js.calls.where((c) => c.startsWith('__kmepBgMint(')).length, 2);
  });

  test('bindingResolver подменяет contentBinding', () async {
    final p = makeProvider(bindings: () => {'videoX': 'VISITOR-DATA'});
    await p.tokenFor('videoX');
    final mintCall = js.calls.firstWhere((c) => c.startsWith('__kmepBgMint('));
    expect(mintCall, contains('VISITOR-DATA'));
  });

  test('деградация (R3): hex-ответ -> null, без исключения', () async {
    js.degradeSnapshot = true;
    final p = makeProvider();
    final pot = await p.tokenFor('video1');
    expect(pot, isNull);
    expect(p.lastError, contains('деградировал'));
    expect(generateItCalls, isEmpty); // до GenerateIT не дошли
  });

  test('GenerateIT 400 (R2): отказ валидации -> null', () async {
    final p = makeProvider(
        generateItResponder: (_, __) => 'HTTP400'); // не '[' -> имитация отказа
    final pot = await p.tokenFor('video1');
    expect(pot, isNull);
    expect(p.lastError, contains('GenerateIT'));
  });

  test('нет wpo -> null (минтинг невозможен)', () async {
    js.dropWpo = true;
    final p = makeProvider();
    expect(await p.tokenFor('video1'), isNull);
    expect(p.lastError, contains('webPoSignalOutput'));
  });

  test('ошибка минтинга -> null', () async {
    js.failMint = true;
    final p = makeProvider();
    expect(await p.tokenFor('video1'), isNull);
    expect(p.lastError, contains('mint'));
  });

  test('parseLooseJson: одинарные кавычки, \\xNN, висячие запятые', () {
    final m = parseLooseJson("{a:'x\\x41y',b:[1,2,],c:'{\"k\":1}',d:2,}");
    expect(m['a'], 'xAy');
    expect(m['b'], [1, 2]);
    expect(m['c'], {'k': 1});
    expect(m['d'], 2);
  });
}
