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

/// PO token — аттестационный токен YouTube (BotGuard), которым привязывается
/// сессия к «настоящему» браузеру/устройству. Без него часть клиентов
/// (IOS, WEB на подозрительных IP) отдаёт урезанные ответы или 403 на CDN.
///
/// Абстракция сознательно минимальная: провайдер умеет выдавать токен для
/// конкретного видео. Оркестратор сам решает, куда его воткнуть:
///   - в тело player-запроса (serviceIntegrityDimensions.poToken);
///   - параметром pot= в googlevideo-URL стримов.
///
/// БИНДИНГ токена (важно!):
///   - по умолчанию videoId (gvs-эксперимент html5_generate_content_po_token);
///   - для WEB без этого эксперимента токен привязывается к visitorData —
///     передавайте её как binding.
abstract class PoTokenProvider {
  /// Токен для конкретного видео или null, если выдать не удалось.
  /// Провайдер НЕ должен бросать исключений наружу ради null.
  Future<String?> tokenFor(String videoId);
}

/// Дефолт: токенов нет. Оркестратор работает как раньше.
class NoOpPoTokenProvider implements PoTokenProvider {
  const NoOpPoTokenProvider();

  @override
  Future<String?> tokenFor(String videoId) async => null;
}

/// Генерация POT через официальный скрипт bgutil-ytdlp-pot-provider
/// (Brainicism/bgutil-ytdlp-pot-provider, server/build/generate_once.js).
///
/// Скрипт сам решает BotGuard-челлендж через Node. Первая генерация занимает
/// 10-20 c (потом кэш в ~/.config/bgutil-ytdlp-pot-provider).
class BgutilScriptPoTokenProvider implements PoTokenProvider {
  final String scriptPath;
  final String nodeExecutable;
  final Duration timeout;

  /// {videoId: contentBinding} — переопределение биндинга (например
  /// visitorData для WEB-клиента).
  final Map<String, String> Function() bindingResolver;

  BgutilScriptPoTokenProvider({
    required this.scriptPath,
    this.nodeExecutable = 'node',
    this.timeout = const Duration(seconds: 90),
    Map<String, String> bindingOverrides = const {},
  }) : bindingResolver = (() => bindingOverrides);

  BgutilScriptPoTokenProvider.withResolver({
    required this.scriptPath,
    this.nodeExecutable = 'node',
    this.timeout = const Duration(seconds: 90),
    Map<String, String> Function()? bindingResolver,
  }) : bindingResolver = bindingResolver ?? (() => const {});

  @override
  Future<String?> tokenFor(String videoId) async {
    final binding = bindingResolver()[videoId] ?? videoId;
    try {
      final result = await Process.run(
        nodeExecutable,
        [scriptPath, '-c', binding],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);
      // Последняя строка stdout — JSON {"contentBinding","poToken","expiresAt"}.
      final lines = result.stdout.toString().trim().split('\n');
      if (result.exitCode != 0 || lines.isEmpty) return null;
      final json = jsonDecode(lines.last) as Map<String, dynamic>;
      return json['poToken'] as String?;
    } catch (_) {
      return null; // деградация без исключения — контракт PoTokenProvider
    }
  }
}

/// Генерация POT через постоянно запущенный HTTP-сервер bgutil
/// (node build/main.js, порт 4416). Быстрее скрипта: держит прогретую
/// BotGuard-сессию.
class BgutilHttpPoTokenProvider implements PoTokenProvider {
  final Uri baseUrl;
  final Duration timeout;
  final Map<String, String> Function() bindingResolver;

  BgutilHttpPoTokenProvider({
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 30),
    Map<String, String> bindingOverrides = const {},
  })  : baseUrl = baseUrl ?? Uri.parse('http://127.0.0.1:4416'),
        bindingResolver = (() => bindingOverrides);

  @override
  Future<String?> tokenFor(String videoId) async {
    final binding = bindingResolver()[videoId] ?? videoId;
    final client = HttpClient();
    try {
      final req = await client
          .postUrl(baseUrl.replace(path: '/get_pot'))
          .timeout(timeout);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'content_binding': binding}));
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join().timeout(timeout);
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['poToken'] as String?;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
