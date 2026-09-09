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

import 'dart:convert';

class RemoteConfig {
  final String kmepVersion;
  final List<String> clientPriority;
  final bool enableEmbeddedYtdlp;
  final String? backendEndpoint;
  final int backendTimeoutMs;
  final int nsigCacheTtlHours;
  final bool poTokenRequired;
  final bool emergencyMode;
  final int maxRetriesPerClient;
  final bool parallelFetch;
  final int targetMinHeight;

  /// Хотфиксы конфигураций InnerTube-клиентов без релиза приложения:
  /// {"IOS": {"clientVersion": "19.45.4", "userAgent": "..."}, ...}.
  /// Ключи верхнего уровня — id клиента из ClientRegistry; известные поля
  /// применяются поверх дефолтов, неизвестные игнорируются.
  final Map<String, Map<String, dynamic>> clientOverrides;

  const RemoteConfig({
    this.kmepVersion = '1.0',
    this.clientPriority = const [
      'ANDROID_VR',
      'WEB',
      'IOS',
      'WEB_SAFARI',
      'TV'
    ],
    this.enableEmbeddedYtdlp = true,
    this.backendEndpoint,
    this.backendTimeoutMs = 5000,
    this.nsigCacheTtlHours = 24,
    this.poTokenRequired = false,
    this.emergencyMode = false,
    this.maxRetriesPerClient = 2,
    this.parallelFetch = false,
    this.targetMinHeight = 1080,
    this.clientOverrides = const {},
  });

  factory RemoteConfig.fromJson(Map<String, dynamic> json) => RemoteConfig(
        kmepVersion: json['kmep_version'] as String? ?? '1.0',
        clientPriority: (json['client_priority'] as List?)?.cast<String>() ??
            const ['ANDROID_VR', 'WEB', 'IOS', 'WEB_SAFARI', 'TV'],
        enableEmbeddedYtdlp: json['enable_embedded_ytdlp'] as bool? ?? true,
        backendEndpoint: json['backend_endpoint'] as String?,
        backendTimeoutMs: (json['backend_timeout_ms'] as num?)?.toInt() ?? 5000,
        nsigCacheTtlHours:
            (json['nsig_cache_ttl_hours'] as num?)?.toInt() ?? 24,
        poTokenRequired: json['po_token_required'] as bool? ?? false,
        emergencyMode: json['emergency_mode'] as bool? ?? false,
        maxRetriesPerClient:
            (json['max_retries_per_client'] as num?)?.toInt() ?? 2,
        parallelFetch: json['parallel_fetch'] as bool? ?? false,
        targetMinHeight: (json['target_min_height'] as num?)?.toInt() ?? 1080,
        clientOverrides:
            (json['client_overrides'] as Map<String, dynamic>?)?.map(
                  (k, v) =>
                      MapEntry(k, (v as Map<String, dynamic>?) ?? const {}),
                ) ??
                const {},
      );

  Map<String, dynamic> toJson() => {
        'kmep_version': kmepVersion,
        'client_priority': clientPriority,
        'enable_embedded_ytdlp': enableEmbeddedYtdlp,
        'backend_endpoint': backendEndpoint,
        'backend_timeout_ms': backendTimeoutMs,
        'nsig_cache_ttl_hours': nsigCacheTtlHours,
        'po_token_required': poTokenRequired,
        'emergency_mode': emergencyMode,
        'max_retries_per_client': maxRetriesPerClient,
        'parallel_fetch': parallelFetch,
        'target_min_height': targetMinHeight,
        'client_overrides': clientOverrides,
      };
}

class RemoteConfigLoader {
  final Future<String?> Function() fetchRemoteJson;
  final Future<void> Function(String json) persistLocally;
  final Future<String?> Function() readLocal;

  RemoteConfigLoader({
    required this.fetchRemoteJson,
    required this.persistLocally,
    required this.readLocal,
  });

  Future<RemoteConfig> load() async {
    try {
      final remote = await fetchRemoteJson();
      if (remote != null) {
        await persistLocally(remote);
        return RemoteConfig.fromJson(_decode(remote));
      }
    } catch (_) {}

    try {
      final local = await readLocal();
      if (local != null) return RemoteConfig.fromJson(_decode(local));
    } catch (_) {}

    return const RemoteConfig();
  }

  Map<String, dynamic> _decode(String json) =>
      jsonDecode(json) as Map<String, dynamic>;
}
