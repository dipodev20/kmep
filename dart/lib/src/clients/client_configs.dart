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

/// Конфигурация одного InnerTube-клиента: заголовки, context-блок для тела
/// запроса, и метаданные, которые использует Orchestrator для приоритезации.
///
/// ВАЖНО (откалибровано живым прогоном 2026-08-22, tool/client_matrix.js):
/// - в ТЕЛЕ запроса client.clientName — СТРОКА ('ANDROID_VR'), а в заголовке
///   X-YouTube-Client-Name — ЧИСЛО ('28'). Это разные поля: bodyClientName и
///   headerClientName.
/// - ANDROID_VR работает БЕЗ ?key= (noApiKey) и отдаёт все форматы прямыми
///   url с уже применённой подписью и БЕЗ параметра n — player.js для него
///   не нужен вообще (подтверждено Range-чеками, HTTP 206).
/// - WEB работает только с signatureTimestamp из watch-страницы (STS) и
///   требует полного пайплайна player.js (sig+nsig).
class InnerTubeClientConfig {
  final String id;
  final String bodyClientName;
  final String clientVersion;
  final String userAgent;

  /// Числовое имя для заголовка X-YouTube-Client-Name (null = не слать).
  final String? headerClientName;
  final String apiKey;

  /// Не добавлять ?key= к эндпоинту (нужно для ANDROID_VR).
  final bool noApiKey;

  /// Browser-клиенты без signatureTimestamp в playbackContext отдают
  /// UNPLAYABLE — для них оркестратор подкладывает STS из watch-страницы.
  final bool needsSignatureTimestamp;

  /// Клиенту нужен visitorData (TVHTML5): оркестратор подкладывает строку
  /// из ytcfg watch-страницы в context.client.visitorData и заголовок
  /// X-Goog-Visitor-Id. Без неё TV отдаёт UNPLAYABLE "page needs to be
  /// reloaded"; с ней работает НЕСТАБИЛЬНО с датацентровых IP (проверено:
  /// единичные успехи) — гейтится той же репутацией IP, что и POT.
  final bool needsVisitorData;
  final bool requiresPoToken;
  final bool supportsSabrOnly;
  final String maxQuality;

  /// Доп. поля внутрь context.client (androidSdkVersion, deviceModel, ...).
  final Map<String, dynamic> extraContext;

  const InnerTubeClientConfig({
    required this.id,
    required this.bodyClientName,
    required this.clientVersion,
    required this.userAgent,
    this.headerClientName,
    this.apiKey = '',
    this.noApiKey = false,
    this.needsSignatureTimestamp = false,
    this.needsVisitorData = false,
    this.requiresPoToken = false,
    this.supportsSabrOnly = false,
    this.maxQuality = '1080p',
    this.extraContext = const {},
  });

  Map<String, dynamic> buildContext(
          {String hl = 'en', String gl = 'US', String? visitorData}) =>
      {
        'client': {
          'clientName': bodyClientName,
          'clientVersion': clientVersion,
          'hl': hl,
          'gl': gl,
          ...extraContext,
          if (visitorData != null) 'visitorData': visitorData,
        },
      };

  Map<String, String> buildHeaders({String? visitorData}) => {
        'User-Agent': userAgent,
        'Content-Type': 'application/json',
        if (headerClientName != null)
          'X-YouTube-Client-Name': headerClientName!,
        if (headerClientName != null) 'X-YouTube-Client-Version': clientVersion,
        if (visitorData != null) 'X-Goog-Visitor-Id': visitorData,
      };

  Uri _endpoint(String op) => noApiKey || apiKey.isEmpty
      ? Uri.parse('https://www.youtube.com/youtubei/v1/$op')
      : Uri.parse('https://www.youtube.com/youtubei/v1/$op?key=$apiKey');

  Uri playerEndpoint() => _endpoint('player');
  Uri browseEndpoint() => _endpoint('browse');
  Uri searchEndpoint() => _endpoint('search');
  Uri nextEndpoint() => _endpoint('next');

  InnerTubeClientConfig copyWith({
    String? bodyClientName,
    String? clientVersion,
    String? userAgent,
    String? headerClientName,
    String? apiKey,
    bool? noApiKey,
    bool? needsSignatureTimestamp,
    bool? needsVisitorData,
    bool? requiresPoToken,
    bool? supportsSabrOnly,
    String? maxQuality,
    Map<String, dynamic>? extraContext,
  }) =>
      InnerTubeClientConfig(
        id: id,
        bodyClientName: bodyClientName ?? this.bodyClientName,
        clientVersion: clientVersion ?? this.clientVersion,
        userAgent: userAgent ?? this.userAgent,
        headerClientName: headerClientName ?? this.headerClientName,
        apiKey: apiKey ?? this.apiKey,
        noApiKey: noApiKey ?? this.noApiKey,
        needsSignatureTimestamp:
            needsSignatureTimestamp ?? this.needsSignatureTimestamp,
        needsVisitorData: needsVisitorData ?? this.needsVisitorData,
        requiresPoToken: requiresPoToken ?? this.requiresPoToken,
        supportsSabrOnly: supportsSabrOnly ?? this.supportsSabrOnly,
        maxQuality: maxQuality ?? this.maxQuality,
        extraContext: extraContext ?? this.extraContext,
      );
}

/// Реестр клиентов. Значения выверены по репликам yt-dlp 2026.08
/// (tool/client_matrix_ytdlp.js): все клиенты теперь БЕЗ ?key= (keyless
/// InnerTube), версии/UA — точные копии рабочих.
///
/// Ключи ниже — ПУБЛИЧНЫЕ InnerTube-константы (не секреты проекта).
class ClientRegistry {
  static const androidVr = InnerTubeClientConfig(
    id: 'ANDROID_VR',
    bodyClientName: 'ANDROID_VR',
    headerClientName: '28',
    clientVersion: '1.65.10',
    userAgent:
        'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
    noApiKey: true,
    // GVS PO политика yt-dlp: required для https/dash.
    requiresPoToken: true,
    maxQuality: '2160p',
    extraContext: {
      'deviceMake': 'Oculus',
      'deviceModel': 'Quest 3',
      'androidSdkVersion': 32,
      'osName': 'Android',
      'osVersion': '12L',
    },
  );

  /// Запрос валиден (status OK), но без PO token отдаёт только SABR-
  /// дескрипторы без URL. Станет полезен вместе с PoTokenProvider.
  static const ios = InnerTubeClientConfig(
    id: 'IOS',
    bodyClientName: 'IOS',
    headerClientName: '5',
    clientVersion: '21.26.4',
    userAgent:
        'com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
    noApiKey: true,
    requiresPoToken: true,
    maxQuality: '1080p',
    extraContext: {
      'deviceMake': 'Apple',
      'deviceModel': 'iPhone16,2',
      'osName': 'iPhone',
      'osVersion': '18.3.2.22D82',
    },
  );

  static const web = InnerTubeClientConfig(
    id: 'WEB',
    bodyClientName: 'WEB',
    headerClientName: '1',
    // Сознательно НЕ самая свежая: с этой версией проверен весь пайплайн
    // sig/nsig через player.js. Свежую можно подать через clientOverrides.
    clientVersion: '2.20240808.00.00',
    userAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
    noApiKey: true,
    needsSignatureTimestamp: true,
    // GVS PO политика yt-dlp для web: required (кроме premium-контента).
    requiresPoToken: true,
    maxQuality: '2160p',
  );

  /// В yt-dlp "web_safari" — это ОБЫЧНЫЙ WEB с Safari-UA (clientName WEB!).
  /// Без cookies сейчас UNPLAYABLE, оставлен как конфиг на будущее.
  static const webSafari = InnerTubeClientConfig(
    id: 'WEB_SAFARI',
    bodyClientName: 'WEB',
    headerClientName: '1',
    clientVersion: '2.20260708.00.00',
    userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)',
    noApiKey: true,
    needsSignatureTimestamp: true,
    maxQuality: '1080p',
  );

  /// Точная реплика yt-dlp, но без visitorData всё ещё UNPLAYABLE ("page
  /// needs to be reloaded"). Заведётся вместе с visitorData/POT.
  static const tv = InnerTubeClientConfig(
    id: 'TV',
    bodyClientName: 'TVHTML5',
    headerClientName: '7',
    clientVersion: '7.20260707.07.00',
    userAgent:
        'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)',
    noApiKey: true,
    needsVisitorData: true,
    maxQuality: '1080p',
  );

  static const List<InnerTubeClientConfig> all = [
    androidVr,
    ios,
    web,
    webSafari,
    tv,
  ];

  static InnerTubeClientConfig byId(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => androidVr);

  /// Дефолтная конфигурация клиента с поверх RemoteConfig-оверрайдами.
  ///
  /// Известные ключи override-мапы: bodyClientName, clientVersion,
  /// userAgent, headerClientName, apiKey, noApiKey,
  /// needsSignatureTimestamp, requiresPoToken, supportsSabrOnly,
  /// maxQuality, extraContext. Неизвестные ключи молча игнорируются —
  /// старые конфиги не должны ломать новые версии приложения.
  static InnerTubeClientConfig resolved(
    String id, {
    Map<String, Map<String, dynamic>> overrides = const {},
  }) {
    final base = byId(id);
    final o = overrides[id];
    if (o == null) return base;
    String? str(String k) => o[k] is String ? o[k] as String : null;
    bool? boolV(String k) => o[k] is bool ? o[k] as bool : null;
    return base.copyWith(
      bodyClientName: str('bodyClientName'),
      clientVersion: str('clientVersion'),
      userAgent: str('userAgent'),
      headerClientName: str('headerClientName'),
      apiKey: str('apiKey'),
      noApiKey: boolV('noApiKey'),
      needsSignatureTimestamp: boolV('needsSignatureTimestamp'),
      needsVisitorData: boolV('needsVisitorData'),
      requiresPoToken: boolV('requiresPoToken'),
      supportsSabrOnly: boolV('supportsSabrOnly'),
      maxQuality: str('maxQuality'),
      extraContext: o['extraContext'] is Map<String, dynamic>
          ? o['extraContext'] as Map<String, dynamic>
          : null,
    );
  }
}
