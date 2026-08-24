import 'dart:convert';
import 'package:http/http.dart' as http;

import 'client_configs.dart';
import '../models/kmep_models.dart';

/// Тонкая обёртка вокруг одного InnerTube-клиента: собирает тело запроса,
/// шлёт его, отдаёт распарсенный JSON. Ничего не знает про Orchestrator —
/// он выше по стеку и решает, к кому идти и в каком порядке.
class InnerTubeClient {
  final InnerTubeClientConfig config;
  final http.Client _http;
  final Duration timeout;

  InnerTubeClient(this.config, {http.Client? httpClient, this.timeout = const Duration(seconds: 8)})
      : _http = httpClient ?? http.Client();

  Future<Map<String, dynamic>> fetchPlayer(
    String videoId, {
    String? poToken,
    int? signatureTimestamp,
    String? visitorData,
    String hl = 'en',
    String gl = 'US',
  }) async {
    final body = {
      'context': config.buildContext(visitorData: visitorData, hl: hl, gl: gl),
      'videoId': videoId,
      'contentCheckOk': true,
      'racyCheckOk': true,
      // WEB и другие browser-клиенты без STS отдают UNPLAYABLE.
      if (signatureTimestamp != null)
        'playbackContext': {
          'contentPlaybackContext': {'signatureTimestamp': signatureTimestamp},
        },
      if (poToken != null) 'serviceIntegrityDimensions': {'poToken': poToken},
    };
    return _post(
      config.playerEndpoint(),
      body,
      'player',
      visitorData: visitorData,
    );
  }

  Future<Map<String, dynamic>> fetchNext(String videoId,
      {String? continuation, String hl = 'en', String gl = 'US'}) async {
    final body = {
      'context': config.buildContext(hl: hl, gl: gl),
      if (continuation != null) 'continuation': continuation else 'videoId': videoId,
    };
    return _post(config.nextEndpoint(), body, 'next');
  }

  Future<Map<String, dynamic>> fetchBrowse(String browseId,
      {String? params, String? continuation, String hl = 'en', String gl = 'US'}) async {
    final body = {
      'context': config.buildContext(hl: hl, gl: gl),
      if (continuation != null) 'continuation': continuation else 'browseId': browseId,
      if (params != null) 'params': params,
    };
    return _post(config.browseEndpoint(), body, 'browse');
  }

  /// [params] — InnerTube-фильтры поиска в protobuf-base64 (например
  /// '8gEBGgIgAQ==' = только шортсы, как чип «Shorts» в поиске YouTube).
  Future<Map<String, dynamic>> fetchSearch(String query,
      {String? continuation, String? params, String hl = 'en', String gl = 'US'}) async {
    final body = {
      'context': config.buildContext(hl: hl, gl: gl),
      if (continuation != null)
        'continuation': continuation
      else ...{
        'query': query,
        if (params != null) 'params': params,
      },
    };
    return _post(config.searchEndpoint(), body, 'search');
  }

  Future<Map<String, dynamic>> _post(
    Uri uri,
    Map<String, dynamic> body,
    String op, {
    String? visitorData,
  }) async {
    try {
      final resp = await _http
          .post(
            uri,
            headers: config.buildHeaders(visitorData: visitorData),
            body: jsonEncode(body),
          )
          .timeout(timeout);

      if (resp.statusCode == 429) {
        throw KMEPException(KMEPErrorCode.rateLimited, 'Rate limited on $op', clientId: config.id);
      }
      if (resp.statusCode != 200) {
        throw KMEPException(
          KMEPErrorCode.networkError,
          'HTTP ${resp.statusCode} on $op',
          clientId: config.id,
        );
      }
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } on KMEPException {
      rethrow;
    } catch (e) {
      throw KMEPException(KMEPErrorCode.networkError, 'Request failed: $e', clientId: config.id, cause: e);
    }
  }

  void close() => _http.close();
}
