import 'dart:convert';
import 'dart:io';

Future<void> probe(String videoId) async {
  final body = jsonEncode({
    'videoId': videoId,
    'contentCheckOk': true,
    'racyCheckOk': true,
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'gl': 'US',
        'hl': 'en',
      },
    },
  });
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse(
        'https://www.youtube.com/youtubei/v1/player?prettyPrint=false'));
    req.headers.set('content-type', 'application/json');
    req.headers.set('user-agent',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
        '(KHTML, like Gecko) Version/26.0 Safari/605.1.15');
    req.headers.set('x-youtube-client-name', '101');
    req.headers.set('x-youtube-client-version', '1.02');
    req.write(body);
    final resp = await req.close().timeout(const Duration(seconds: 20));
    final raw = await resp.transform(utf8.decoder).join();
    print('== $videoId: HTTP ${resp.statusCode}, ${raw.length} байт');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final ps = j['playabilityStatus'] as Map<String, dynamic>?;
    print('   status=${ps?['status']} reason=${ps?['reason'] ?? '-'}');
    final sd = j['streamingData'] as Map<String, dynamic>?;
    final formats = <Map>[];
    if (sd?['formats'] is List) formats.addAll((sd!['formats'] as List).cast<Map>());
    if (sd?['adaptiveFormats'] is List) formats.addAll((sd!['adaptiveFormats'] as List).cast<Map>());
    final withUrl = formats.where((f) => f['url'] != null).toList();
    print('   форматов=${formats.length}, с прямым url=${withUrl.length}');
    if (withUrl.isNotEmpty) {
      final best = withUrl.map((f) => (f['height'] ?? 0) as int).reduce((a, b) => a > b ? a : b);
      final f0 = withUrl.first;
      final url = f0['url'] as String;
      print('   maxH=$best; пример: itag=${f0['itag']} ${f0['mimeType']}');
      // Range-чек первого URL
      final u = Uri.parse(url);
      final hc = HttpClient();
      try {
        final r2 = await hc.openUrl('GET', u);
        r2.headers.set('range', 'bytes=0-1023');
        final resp2 = await r2.close().timeout(const Duration(seconds: 15));
        await resp2.drain();
        print('   Range-чек: HTTP ${resp2.statusCode} ${resp2.headers.contentType}');
      } finally {
        hc.close();
      }
    }
    final visitor = (j['responseContext'] as Map<String, dynamic>?)?['visitorData'];
    print('   visitorData из ответа: ${visitor != null ? "есть (${(visitor as String).length} симв)" : "нет"}');
  } finally {
    client.close();
  }
}

void main() async {
  await probe('dQw4w9WgXcQ');
  await probe('n61ULEU7CO0');
}
