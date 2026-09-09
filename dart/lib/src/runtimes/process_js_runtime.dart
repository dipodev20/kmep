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
import 'dart:io';

import '../models/kmep_models.dart';
import '../resolvers/stream_resolver.dart';

/// JsRuntime поверх внешнего node-процесса.
///
/// НАЗНАЧЕНИЕ: прототип и живая диагностика на десктопе (tool/e2e_live_test.dart
/// гоняет полный Dart-пайплайн через него). В проде на мобильных используется
/// flutter_js (flutter_integration/) — интерфейс JsRuntime один и тот же.
///
/// ПРОТОКОЛ: один длинноживущий child-process, построчный обмен по stdio.
///   -> {"id":N,"type":"load","path":"..."}   выполнить файл (bootstrap)
///   -> {"id":N,"type":"eval","expression":"..."}  выполнить выражение
///   <- @@KMEP@@{"id":N,"ok":true,"val":"..."} | {"id":N,"ok":false,"err":"..."}
///
/// Почему не spawn-per-call: bootstrap (шим + 2.5 МБ player.js) занимает
/// секунды — на каждый формат это недопустимо; состояние (_yt_player,
/// __closureFns, __kmepResolveFn) должно жить между вызовами.
///
/// ОГРАНИЧЕНИЯ (осознанные для прототипа):
/// - если child умрёт (например таймаут на вечном цикле), состояние теряется;
///   следующий вызов поднимет новый процесс, но bootstrap придётся звать
///   заново — резолверу об этом знать нечего, поэтому после таймаута
///   рекомендуется пересоздать StreamResolver.
/// - console внутри player.js заглушён, чтобы не ломать протокол.
class NodeProcessJsRuntime implements JsRuntime {
  final String nodeExecutable;
  final Duration callTimeout;

  Process? _process;
  int _nextId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final StringBuffer _buffer = StringBuffer();
  StreamSubscription<String>? _stdoutSub;

  static const _marker = '@@KMEP@@';

  NodeProcessJsRuntime({
    this.nodeExecutable = 'node',
    this.callTimeout = const Duration(seconds: 30),
  });

  static String get childScript => '''
const fs = require('fs');
process.on('unhandledRejection', function() {});
// Глушим console ДО загрузки скриптов: player.js много пишет, а stdout —
// транспорт протокола.
for (const k of ['log', 'info', 'warn', 'error', 'debug', 'trace']) {
  console[k] = function() {};
}
const rl = require('readline').createInterface({ input: process.stdin, terminal: false });
function reply(obj) { process.stdout.write('$_marker' + JSON.stringify(obj) + '\\n'); }
rl.on('line', function(line) {
  if (!line.trim()) return;
  let msg;
  try { msg = JSON.parse(line); } catch (e) { reply({ id: -1, ok: false, err: 'bad line: ' + e.message }); return; }
  try {
    if (msg.type === 'load') {
      // Косвенный eval: top-level var становятся глобалами, как vm-песочница
      // в Node-диагностике.
      (0, eval)(fs.readFileSync(msg.path, 'utf8'));
      reply({ id: msg.id, ok: true, val: null });
    } else {
      const val = (0, eval)(msg.expression);
      reply({ id: msg.id, ok: true, val: val === undefined || val === null ? null : String(val) });
    }
  } catch (e) {
    reply({ id: msg.id, ok: false, err: String((e && e.message) || e) });
  }
});
''';

  Future<void> _ensureStarted() async {
    if (_process != null) return;
    final dir = await Directory.systemTemp.createTemp('kmep_js_');
    final childFile = File('${dir.path}/child.js');
    await childFile.writeAsString(childScript);
    final proc = await Process.start(nodeExecutable, [childFile.path]);
    _process = proc;
    _stdoutSub = proc.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_onData);
    proc.stderr
        .transform(utf8.decoder)
        .listen((_) {}); // шум диагностик — глушим
    proc.exitCode.then((code) {
      _process = null;
      for (final c in _pending.values) {
        if (!c.isCompleted) {
          c.completeError(KMEPException(
            KMEPErrorCode.nsigFail,
            'JS-процесс завершился (code=$code), состояние потеряно',
          ));
        }
      }
      _pending.clear();
      dir.delete(recursive: true).ignore();
    });
  }

  void _onData(String chunk) {
    _buffer.write(chunk);
    while (true) {
      final text = _buffer.toString();
      final idx = text.indexOf(_marker);
      if (idx == -1) {
        // Мусор без маркера не копим безразмерно.
        if (_buffer.length > (1 << 20)) _buffer.clear();
        return;
      }
      final nl = text.indexOf('\n', idx);
      if (nl == -1) return;
      final line = text.substring(idx + _marker.length, nl);
      _buffer.clear();
      _buffer.write(text.substring(nl + 1));
      try {
        final msg = jsonDecode(line) as Map<String, dynamic>;
        final id = msg['id'] as int;
        final completer = _pending.remove(id);
        if (completer != null && !completer.isCompleted) {
          completer.complete(msg);
        }
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> payload) {
    final id = ++_nextId;
    payload['id'] = id;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _process!.stdin.writeln(jsonEncode(payload));
    return completer.future;
  }

  @override
  Future<void> bootstrap(String script) => bootstrapParts([script]);

  @override
  Future<void> bootstrapParts(List<String> parts) async {
    await _ensureStarted();
    final dir = await Directory.systemTemp.createTemp('kmep_bootstrap_');
    try {
      for (var i = 0; i < parts.length; i++) {
        // Каждый part — самостоятельный top-level скрипт: пишем во
        // временный файл и грузим отдельным load (eval внутри части не
        // нужен, у Node и так глобальный скоуп).
        final scriptFile = File('${dir.path}/part_$i.js');
        await scriptFile.writeAsString(parts[i], flush: true);
        final res = await _request({'type': 'load', 'path': scriptFile.path})
            .timeout(callTimeout);
        if (res['ok'] != true) {
          throw KMEPException(
            KMEPErrorCode.nsigFail,
            'bootstrap player.js упал (часть ${i + 1}/${parts.length}): ${res['err']}',
          );
        }
      }
    } on TimeoutException {
      throw KMEPException(
          KMEPErrorCode.nsigFail, 'bootstrap player.js: таймаут');
    } finally {
      dir.delete(recursive: true).ignore();
    }
  }

  @override
  Future<String> call(String expression) async {
    if (_process == null) {
      throw const KMEPException(KMEPErrorCode.nsigFail,
          'JS-процесс не запущен (bootstrap не вызван?)');
    }
    final Map<String, dynamic> res;
    try {
      res = await _request({'type': 'eval', 'expression': expression})
          .timeout(callTimeout);
    } on TimeoutException {
      _kill();
      throw KMEPException(KMEPErrorCode.nsigFail, 'JS-вызов: таймаут');
    }
    if (res['ok'] != true) {
      throw KMEPException(
          KMEPErrorCode.nsigFail, 'JS-вызов упал: ${res['err']}');
    }
    final val = res['val'];
    if (val is! String) {
      throw const KMEPException(
          KMEPErrorCode.nsigFail, 'JS-вызов вернул не строку');
    }
    return val;
  }

  void _kill() {
    _process?.kill();
    _process = null;
  }

  void dispose() {
    _kill();
    _stdoutSub?.cancel();
  }
}
