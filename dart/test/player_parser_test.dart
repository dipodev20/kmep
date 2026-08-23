import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:kmep_proto/kmep.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('PlayerParser', () {
    test('parses a normal available video', () {
      final response = {
        'playabilityStatus': {'status': 'OK'},
        'videoDetails': {
          'videoId': 'abc123',
          'title': 'Test Video',
          'shortDescription': 'desc',
          'lengthSeconds': '120',
          'viewCount': '1000',
          'channelId': 'UC123',
          'author': 'Test Channel',
          'isLive': false,
          'thumbnail': {
            'thumbnails': [
              {'url': 'https://example.com/thumb.jpg'}
            ]
          },
          'keywords': ['tag1', 'tag2'],
        },
        'microformat': {
          'playerMicroformatRenderer': {
            'publishDate': '2024-01-01',
            'category': 'Music',
          }
        },
        'streamingData': {
          'formats': [
            {
              'itag': 18,
              'url': 'https://googlevideo.com/videoplayback?a=1',
              'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
              'qualityLabel': '360p',
              'width': 640,
              'height': 360,
              'bitrate': 500000,
            }
          ],
          'adaptiveFormats': [
            {
              'itag': 251,
              'url': 'https://googlevideo.com/videoplayback?a=2',
              'mimeType': 'audio/webm; codecs="opus"',
              'bitrate': 160000,
            }
          ],
        },
      };

      final video = PlayerParser.parse(response, fallbackVideoId: 'fallback');

      expect(video.videoId, 'abc123');
      expect(video.title, 'Test Video');
      expect(video.durationSeconds, 120);
      expect(video.viewCount, 1000);
      expect(video.channelName, 'Test Channel');
      expect(video.streams.length, 2);
      expect(video.streams.first.codec, 'avc1.42001E, mp4a.40.2');
      expect(video.streams.last.type, 'audio');
      expect(video.isLive, false);
    });

    test('throws KMEPException for ERROR status', () {
      final response = {
        'playabilityStatus': {'status': 'ERROR', 'reason': 'Video unavailable'},
      };

      expect(
        () => PlayerParser.parse(response, fallbackVideoId: 'x'),
        throwsA(isA<KMEPException>().having((e) => e.code, 'code', KMEPErrorCode.unavailable)),
      );
    });

    test('форматы без url (SABR-дескрипторы, cipher) не становятся стримами',
        () {
      final response = {
        'playabilityStatus': {'status': 'OK'},
        'videoDetails': {
          'videoId': 'sabr1',
          'title': 't',
          'isLive': false,
          'thumbnail': {'thumbnails': []},
        },
        'streamingData': {
          'adaptiveFormats': [
            {
              // SABR-дескриптор: метаданные есть, url нет.
              'itag': 313,
              'mimeType': 'video/webm; codecs="vp9"',
              'height': 2160,
              'bitrate': 18076636,
            },
            {
              'itag': 18,
              'url': 'https://gv.example/ok',
              'mimeType': 'video/mp4; codecs="avc1.42001E"',
              'height': 360,
            },
          ],
        },
      };

      final video = PlayerParser.parse(response, fallbackVideoId: 'x');
      // Только формат с url попадает в streams...
      expect(video.streams.length, 1);
      expect(video.streams.single.url, 'https://gv.example/ok');
      // ...но сырьё доступно резолверу целиком.
      expect(PlayerParser.rawFormats(response).length, 2);
    });

    test('detects live stream via hlsManifestUrl', () {
      final response = {
        'playabilityStatus': {'status': 'OK'},
        'videoDetails': {
          'videoId': 'live1',
          'title': 'Live Stream',
          'isLive': true,
          'lengthSeconds': '0',
          'viewCount': '500',
          'channelId': 'UC999',
          'author': 'Live Channel',
          'thumbnail': {'thumbnails': []},
        },
        'streamingData': {
          'hlsManifestUrl': 'https://googlevideo.com/live.m3u8',
        },
      };

      final video = PlayerParser.parse(response, fallbackVideoId: 'x');
      expect(video.isLive, true);
      expect(video.hlsManifestUrl, isNotNull);
      expect(video.streams.any((s) => s.type == 'hls'), true);
    });
  });

  group('ClientRegistry', () {
    test('all clients have unique ids', () {
      final ids = ClientRegistry.all.map((c) => c.id).toSet();
      expect(ids.length, ClientRegistry.all.length);
    });

    test('byId falls back to androidVr for unknown id', () {
      final cfg = ClientRegistry.byId('DOES_NOT_EXIST');
      expect(cfg.id, 'ANDROID_VR');
    });
  });

  group('InMemoryCacheManager', () {
    test('stores and retrieves video before ttl expiry', () async {
      final cache = InMemoryCacheManager();
      const video = VideoInfo(
        videoId: 'v1',
        title: 't',
        description: 'd',
        durationSeconds: 10,
        viewCount: 1,
        channelId: 'c1',
        channelName: 'ch',
        thumbnails: [],
        tags: [],
        streams: [],
      );

      await cache.putVideo('v1', video, ttl: const Duration(seconds: 5));
      final got = await cache.getVideo('v1');
      expect(got, isNotNull);
      expect(got!.title, 't');
    });

    test('returns null for missing key', () async {
      final cache = InMemoryCacheManager();
      expect(await cache.getVideo('nope'), isNull);
    });
  });

  group('StreamResolver', () {
    const fakePlayerJs = '(function(g){})(_yt_player);';

    test('cipher format goes through player.js with sp/s, direct clean url does not',
        () async {
      final js = _FakeJsRuntime([
        'https://resolved.example/cipher',
        'https://gv.example/v2?n=CCCCCCCCCCCCCCCC',
      ]);
      var playerJsFetches = 0;
      final resolver = StreamResolver(
        jsRuntime: js,
        fetchPlayerJs: (url) async {
          playerJsFetches++;
          return fakePlayerJs;
        },
      );

      final streams = await resolver.resolve([
        {
          'itag': 18,
          'mimeType': 'video/mp4; codecs="avc1.42001E"',
          'signatureCipher':
              'url=https%3A%2F%2Fgv.example%2Fv%3Fn%3DAAAAAAAAAAAAAAAA&s=CIPHERTEXT&sp=sig',
        },
        {
          'itag': 22,
          'mimeType': 'video/mp4; codecs="avc1.64001F"',
          'url': 'https://gv.example/v2?n=BBBBBBBBBBBBBBBB',
        },
        {
          'itag': 394,
          'mimeType': 'video/mp4; codecs="av01.0.08M.08"',
          'url': 'https://gv.example/v3',
        },
      ], playerJsUrl: 'https://example/player.js');

      expect(playerJsFetches, 1);
      expect(js.bootstrapCount, 1);
      // Только первые два формата требуют вызова player.js.
      expect(js.expressions.length, 2);
      // Первый вызов несёт параметры из signatureCipher.
      expect(js.expressions[0], contains('"https://gv.example/v?n=AAAAAAAAAAAAAAAA"'));
      expect(js.expressions[0], contains('"sig"'));
      expect(js.expressions[0], contains('"CIPHERTEXT"'));
      // Второй — прямой URL без подписи, пустые sig-параметры.
      expect(js.expressions[1], contains('"https://gv.example/v2?n=BBBBBBBBBBBBBBBB"'));
      expect(js.expressions[1], contains('""'));

      expect(streams.length, 3);
      expect(streams[0].url, 'https://resolved.example/cipher');
      // Третий формат прошёл насквозь без изменений.
      expect(streams[2].url, 'https://gv.example/v3');
    });

    test('bootstrap happens once per player.js url', () async {
      final js = _FakeJsRuntime([]);
      final resolver = StreamResolver(
        jsRuntime: js,
        fetchPlayerJs: (url) async => fakePlayerJs,
      );
      await resolver.resolve([], playerJsUrl: 'https://example/player.js');
      await resolver.resolve([], playerJsUrl: 'https://example/player.js');
      await resolver.resolve([], playerJsUrl: 'https://example/other.js');
      expect(js.bootstrapCount, 2);
    });

    test('js failure is wrapped into KMEPException(nsigFail)', () async {
      final js = _FakeJsRuntime([])..throwOnCall = true;
      final resolver = StreamResolver(
        jsRuntime: js,
        fetchPlayerJs: (url) async => fakePlayerJs,
      );

      await expectLater(
        resolver.resolve([
          {
            'itag': 18,
            'mimeType': 'video/mp4',
            'url': 'https://gv.example/v?n=AAAAAAAAAAAAAAAA',
          }
        ], playerJsUrl: 'https://example/player.js'),
        throwsA(isA<KMEPException>().having((e) => e.code, 'code', KMEPErrorCode.nsigFail)),
      );
    });

    test('non-url answer from player.js is rejected', () async {
      final js = _FakeJsRuntime(['   ']);
      final resolver = StreamResolver(
        jsRuntime: js,
        fetchPlayerJs: (url) async => fakePlayerJs,
      );

      await expectLater(
        resolver.resolve([
          {
            'itag': 18,
            'mimeType': 'video/mp4',
            'url': 'https://gv.example/v?n=AAAAAAAAAAAAAAAA',
          }
        ], playerJsUrl: 'https://example/player.js'),
        throwsA(isA<KMEPException>().having((e) => e.code, 'code', KMEPErrorCode.nsigFail)),
      );
    });
  });

  group('ExtractionOrchestrator', () {
    const fakePlayerJs = '(function(g){})(_yt_player);';

    ExtractionOrchestrator buildOrchestrator({
      required List<String> clientPriority,
      required Map<String, dynamic> Function(http.Request req) responder,
      _FakeMetaProvider? metaProvider,
      required _FakeJsRuntime jsRuntime,
    }) {
      final mock = MockClient((req) async {
        try {
          return http.Response(
            jsonEncode(responder(req)),
            200,
            headers: {'content-type': 'application/json'},
          );
        } catch (e) {
          return http.Response(jsonEncode({'mockError': '$e'}), 500);
        }
      });
      return ExtractionOrchestrator(
        config: RemoteConfig(clientPriority: clientPriority),
        cache: InMemoryCacheManager(),
        streamResolver: StreamResolver(
          jsRuntime: jsRuntime,
          fetchPlayerJs: (_) async => fakePlayerJs,
        ),
        // Дефолт: мета доступна (STS + player.js) — переопределяется тестом.
        watchPageMetaProvider: metaProvider ??
            _FakeMetaProvider(
              meta: const WatchPageMeta(
                signatureTimestamp: 20683,
                playerJsUrl: 'https://example/base.js',
              ),
            ),
        httpClientFactory: () => mock,
      );
    }

    test('direct formats от ANDROID_VR: без watch-meta и без JS', () async {
      final meta = _FakeMetaProvider();
      final orchestrator = buildOrchestrator(
        clientPriority: const ['ANDROID_VR'],
        responder: (_) => _okDirectResponse(),
        metaProvider: meta,
        jsRuntime: _FakeJsRuntime([]),
      );

      final video = await orchestrator.fetchVideo('vid1');

      expect(video.videoId, 'vid1');
      expect(video.streams.single.url, 'https://gv.example/direct');
      // ANDROID_VR не требует STS и cipher-резолва — watch-страница не нужна.
      expect(meta.calls, 0);
      orchestrator.dispose();
    });

    test('WEB cipher: STS из watch-meta уходит в тело, резолв через player.js',
        () async {
      final bodies = <Map<String, dynamic>>[];
      final meta = _FakeMetaProvider(
        meta: const WatchPageMeta(signatureTimestamp: 20683, playerJsUrl: 'https://example/base.js'),
      );
      final js = _FakeJsRuntime(['https://resolved.example/final']);
      final orchestrator = buildOrchestrator(
        clientPriority: const ['WEB'],
        responder: (req) {
          bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          return _cipherResponse();
        },
        metaProvider: meta,
        jsRuntime: js,
      );

      final video = await orchestrator.fetchVideo('vid1');

      expect(video.streams.single.url, 'https://resolved.example/final');
      expect(
        bodies.single['playbackContext']['contentPlaybackContext']['signatureTimestamp'],
        20683,
      );
      expect(js.bootstrapCount, 1);
      expect(js.expressions.single, contains('"CIPHERTEXT"'));
      // Meta закэширована: STS и резолв взяли её один раз.
      expect(meta.calls, 1);
      orchestrator.dispose();
    });

    test('meta недоступна для WEB -> UNPLAYABLE без STS -> unavailable', () async {
      final meta = _FakeMetaProvider(fail: true);
      final orchestrator = buildOrchestrator(
        clientPriority: const ['WEB'],
        responder: (req) => req.body.contains('signatureTimestamp')
            ? _cipherResponse()
            : {
                'playabilityStatus': {'status': 'UNPLAYABLE', 'reason': 'STS needed'},
              },
        metaProvider: meta,
        jsRuntime: _FakeJsRuntime([]),
      );

      await expectLater(
        orchestrator.fetchVideo('vid1'),
        throwsA(isA<KMEPException>().having((e) => e.code, 'code', KMEPErrorCode.unavailable)),
      );
      orchestrator.dispose();
    });

    test('кэш: второй вызов не ходит в сеть', () async {
      var httpCalls = 0;
      final orchestrator = buildOrchestrator(
        clientPriority: const ['ANDROID_VR'],
        responder: (_) {
          httpCalls++;
          return _okDirectResponse();
        },
        jsRuntime: _FakeJsRuntime([]),
      );

      final first = await orchestrator.fetchVideo('vid1');
      final second = await orchestrator.fetchVideo('vid1');

      expect(second.videoId, first.videoId);
      expect(httpCalls, 1);
      orchestrator.dispose();
    });

    test('client_overrides из RemoteConfig применяются к запросу', () async {
      final headers = <Map<String, String>>[];
      final mock = MockClient((req) async {
        headers.add(Map.from(req.headers));
        return http.Response(
          jsonEncode(_okDirectResponse()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final orchestrator = ExtractionOrchestrator(
        config: RemoteConfig(
          clientPriority: const ['ANDROID_VR'],
          clientOverrides: {
            'ANDROID_VR': {
              'clientVersion': '9.99.99',
              'userAgent': 'com.test/overridden',
              'неизвестныйКлюч': 'игнорируется',
            },
          },
        ),
        cache: InMemoryCacheManager(),
        streamResolver: StreamResolver(
          jsRuntime: _FakeJsRuntime([]),
          fetchPlayerJs: (_) async => fakePlayerJs,
        ),
        httpClientFactory: () => mock,
      );

      final video = await orchestrator.fetchVideo('vid1');

      expect(video.streams.single.url, 'https://gv.example/direct');
      expect(headers.single['X-YouTube-Client-Version'], '9.99.99');
      expect(headers.single['User-Agent'], 'com.test/overridden');
      orchestrator.dispose();
    });

    test('прямой url с сырым n тоже уходит в player.js (WEB+POT кейс)',
        () async {
      final js = _FakeJsRuntime(['https://resolved.example/with-n']);
      final orchestrator = buildOrchestrator(
        clientPriority: const ['WEB'],
        responder: (_) => {
          'playabilityStatus': {'status': 'OK'},
          'videoDetails': {
            'videoId': 'vid1',
            'title': 't',
            'isLive': false,
            'thumbnail': {'thumbnails': []},
          },
          // WEB+POT кейс: прямой url, БЕЗ cipher, но с сырым n.
          'streamingData': {
            'formats': [
              {
                'itag': 18,
                'url':
                    'https://rr1---sn-x.googlevideo.com/videoplayback?n=RAWRawnRawnRawn&sig=SIG',
                'mimeType': 'video/mp4; codecs="avc1.42001E"',
                'height': 360,
              }
            ],
          },
        },
        jsRuntime: js,
      );

      final video = await orchestrator.fetchVideo('vid1');

      expect(js.expressions.length, 1);
      expect(video.streams.single.url, 'https://resolved.example/with-n');
      orchestrator.dispose();
    });

    test('ClientRegistry.resolved: неизвестные ключи и чужие id безопасны',
        () {
      final cfg = ClientRegistry.resolved(
        'IOS',
        overrides: {
          'IOS': {'clientVersion': '19.45.4', 'bogus': true},
        },
      );
      expect(cfg.clientVersion, '19.45.4');
      expect(cfg.bodyClientName, 'IOS'); // не перезаписано
      // Неизвестный id -> дефолт ANDROID_VR без падения.
      final fallback = ClientRegistry.resolved('NOPE', overrides: {
        'NOPE': {'clientVersion': 'x'},
      });
      expect(fallback.id, 'ANDROID_VR');
    });

    test('po token: уходит в тело запроса и в URL стрима', () async {
      final bodies = <Map<String, dynamic>>[];
      final js = _FakeJsRuntime([
        'https://rr1---sn-x.googlevideo.com/videoplayback?n=DONEnDONE',
      ]);
      final mock = MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'playabilityStatus': {'status': 'OK'},
            'videoDetails': {
              'videoId': 'vid1',
              'title': 't',
              'isLive': false,
              'thumbnail': {'thumbnails': []},
            },
            'streamingData': {
              'formats': [
                {
                  'itag': 18,
                  'url':
                      'https://rr1---sn-x.googlevideo.com/videoplayback?n=AAAAAAAAAAAAAAAA',
                  'mimeType': 'video/mp4; codecs="avc1.42001E"',
                  'height': 360,
                }
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final orchestrator = ExtractionOrchestrator(
        config: const RemoteConfig(clientPriority: ['IOS']),
        cache: InMemoryCacheManager(),
        streamResolver: StreamResolver(
          jsRuntime: js,
          fetchPlayerJs: (_) async => fakePlayerJs,
        ),
        poTokenProvider: _FakePoTokenProvider('TOKEN123'),
        watchPageMetaProvider: _FakeMetaProvider(
          meta: const WatchPageMeta(playerJsUrl: 'https://example/base.js'),
        ),
        httpClientFactory: () => mock,
      );

      final video = await orchestrator.fetchVideo('vid1');

      // IOS requiresPoToken=true -> токен и в теле player-запроса...
      expect(bodies.single['serviceIntegrityDimensions']['poToken'], 'TOKEN123');
      // ...и параметром pot= в googlevideo-URL (после резолва n).
      expect(video.streams.single.url.endsWith('&pot=TOKEN123'), isTrue);
      orchestrator.dispose();
    });

    test('без провайдера или с NoOp всё работает как раньше', () async {
      final bodies = <Map<String, dynamic>>[];
      final mock = MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode(_okDirectResponse()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final orchestrator = ExtractionOrchestrator(
        config: const RemoteConfig(clientPriority: ['ANDROID_VR']),
        cache: InMemoryCacheManager(),
        streamResolver: StreamResolver(
          jsRuntime: _FakeJsRuntime([]),
          fetchPlayerJs: (_) async => fakePlayerJs,
        ),
        poTokenProvider: const NoOpPoTokenProvider(),
        httpClientFactory: () => mock,
      );

      final video = await orchestrator.fetchVideo('vid1');

      // ANDROID_VR не требует POT: тело чистое, url не тронут.
      expect(bodies.single.containsKey('serviceIntegrityDimensions'), isFalse);
      expect(video.streams.single.url.contains('pot='), isFalse);
      orchestrator.dispose();
    });

    test('TV: visitorData из watch-meta попадает в тело и заголовок', () async {
      final bodies = <Map<String, dynamic>>[];
      final headersList = <Map<String, String>>[];
      final mock = MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        headersList.add(Map.from(req.headers));
        return http.Response(
          jsonEncode(_okDirectResponse()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final meta = _FakeMetaProvider(
        meta: const WatchPageMeta(
          signatureTimestamp: 20683,
          visitorData: 'CgtWSVNJVE9SX0RBVEE',
        ),
      );
      final orchestrator = ExtractionOrchestrator(
        config: const RemoteConfig(clientPriority: ['TV']),
        cache: InMemoryCacheManager(),
        streamResolver: StreamResolver(
          jsRuntime: _FakeJsRuntime([]),
          fetchPlayerJs: (_) async => fakePlayerJs,
        ),
        watchPageMetaProvider: meta,
        httpClientFactory: () => mock,
      );

      await orchestrator.fetchVideo('vid1');

      // TV needsVisitorData: VD в context.client.visitorData...
      expect(
        bodies.single['context']['client']['visitorData'],
        'CgtWSVNJVE9SX0RBVEE',
      );
      // ...и заголовком X-Goog-Visitor-Id.
      expect(headersList.single['X-Goog-Visitor-Id'], 'CgtWSVNJVE9SX0RBVEE');
      // TV не требует STS (проверено живьём: с playbackContext ломается).
      expect(bodies.single.containsKey('playbackContext'), isFalse);
      orchestrator.dispose();
    });
  });

  group('PoTokenProviders', () {
    test('BgutilScriptPoTokenProvider парсит poToken из последней строки',
        () async {
      final dir = await Directory.systemTemp.createTemp('kmep_pot_test_');
      final script = File('${dir.path}/generate_once.js');
      await script.writeAsString(
        '#!/bin/sh\necho "шум в stdout"\necho \'{\"contentBinding\":\"vid1\",\"poToken\":\"TOK123\",\"expiresAt\":\"2030-01-01T00:00:00Z\"}\'\n',
      );
      // Шелл-скрипт нельзя исполнять как node — подменяем executable.
      final provider = BgutilScriptPoTokenProvider.withResolver(
        scriptPath: script.path,
        nodeExecutable: '/bin/sh',
      );
      addTearDown(() => dir.delete(recursive: true));

      expect(await provider.tokenFor('vid1'), 'TOK123');
    });

    test('BgutilScriptPoTokenProvider: ошибка скрипта -> null', () async {
      final dir = await Directory.systemTemp.createTemp('kmep_pot_test_');
      final script = File('${dir.path}/generate_once.js');
      await script.writeAsString('#!/bin/sh\nexit 3\n');
      final provider = BgutilScriptPoTokenProvider.withResolver(
        scriptPath: script.path,
        nodeExecutable: '/bin/sh',
      );
      addTearDown(() => dir.delete(recursive: true));

      expect(await provider.tokenFor('vid1'), isNull);
    });

    test('BgutilHttpPoTokenProvider достаёт poToken из /get_pot', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        expect(body, contains('"content_binding":"vid9"'));
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'poToken': 'HTTP_TOK',
          'contentBinding': 'vid9',
          'expiresAt': '2030-01-01T00:00:00Z',
        }));
        await req.response.close();
      });

      final provider =
          BgutilHttpPoTokenProvider(baseUrl: Uri.parse('http://127.0.0.1:${server.port}'));
      expect(await provider.tokenFor('vid9'), 'HTTP_TOK');
    });

    test('BgutilHttpPoTokenProvider: 500 -> null', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((req) async {
        req.response.statusCode = 500;
        await req.response.close();
      });

      final provider =
          BgutilHttpPoTokenProvider(baseUrl: Uri.parse('http://127.0.0.1:${server.port}'));
      expect(await provider.tokenFor('vid1'), isNull);
    });
  });

  group('Infra', () {
    test('DiskPlayerJsCache: качает один раз, второй раз из кэша', () async {
      final dir = await Directory.systemTemp.createTemp('kmep_diskcache_');
      addTearDown(() => dir.delete(recursive: true));
      var downloads = 0;

      final cache = DiskPlayerJsCache(
        cacheDir: dir,
        fetch: (url) async {
          downloads++;
          return 'player-js-for-$url';
        },
      );

      expect(await cache.get('https://example/base.js'), 'player-js-for-https://example/base.js');
      expect(await cache.get('https://example/base.js'), 'player-js-for-https://example/base.js');
      expect(downloads, 1);
      // Файл реально лежит на диске.
      expect(dir.listSync().whereType<File>().length, 1);
    });

    test('HttpRemoteConfigFetcher: 200 -> тело, 404/сеть -> null', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((req) async {
        if (req.uri.path == '/cfg.json') {
          req.response.write('{"client_priority":["ANDROID_VR"]}');
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';

      expect(
          await HttpRemoteConfigFetcher(Uri.parse('$base/cfg.json')).fetch(),
          '{"client_priority":["ANDROID_VR"]}');
      expect(await HttpRemoteConfigFetcher(Uri.parse('$base/nope.json')).fetch(), isNull);
      expect(
          await HttpRemoteConfigFetcher(Uri.parse('http://127.0.0.1:1/x')).fetch(),
          isNull);
    });

    test('RemoteConfigLoader с HTTP-фетчером применяет удалённый конфиг',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((req) async {
        req.response.write(jsonEncode({
          'client_priority': ['WEB', 'ANDROID_VR'],
          'target_min_height': 480,
        }));
        await req.response.close();
      });

      final loader = RemoteConfigLoader(
        fetchRemoteJson:
            HttpRemoteConfigFetcher(Uri.parse('http://127.0.0.1:${server.port}/rc')).fetch,
        persistLocally: (_) async {},
        readLocal: () async => null,
      );
      final cfg = await loader.load();
      expect(cfg.clientPriority, ['WEB', 'ANDROID_VR']);
      expect(cfg.targetMinHeight, 480);
    });
  });
}

class _FakeJsRuntime implements JsRuntime {
  final List<String> answers;
  final expressions = <String>[];
  int bootstrapCount = 0;
  bool throwOnCall = false;

  _FakeJsRuntime(this.answers);

  @override
  Future<void> bootstrap(String script) async {
    bootstrapCount++;
  }

  @override
  Future<String> call(String expression) async {
    if (throwOnCall) throw StateError('js exploded');
    expressions.add(expression);
    if (answers.isEmpty) throw StateError('no canned answer');
    return answers.removeAt(0);
  }
}

class _FakeMetaProvider implements WatchPageMetaProvider {
  final WatchPageMeta? meta;
  final bool fail;
  int calls = 0;
  _FakeMetaProvider({this.meta, this.fail = false});

  @override
  Future<WatchPageMeta?> fetch(String videoId) async {
    calls++;
    if (fail) throw Exception('meta network down');
    return meta;
  }
}

class _FakePoTokenProvider implements PoTokenProvider {
  final String? token;
  _FakePoTokenProvider(this.token);

  @override
  Future<String?> tokenFor(String videoId) async => token;
}

/// Возвращает playerResponse в зависимости от клиента (по заголовку).
Map<String, dynamic> _okDirectResponse() => {
      'playabilityStatus': {'status': 'OK'},
      'videoDetails': {
        'videoId': 'vid1',
        'title': 't',
        'isLive': false,
        'thumbnail': {'thumbnails': []},
      },
      'streamingData': {
        'formats': [
          {
            'itag': 18,
            // БЕЗ n: чистый прямой формат (ANDROID_VR стиль) не требует JS.
            'url': 'https://gv.example/direct',
            'mimeType': 'video/mp4; codecs="avc1.42001E"',
            'qualityLabel': '360p',
            'height': 360,
          }
        ],
      },
    };

Map<String, dynamic> _cipherResponse() => {
      'playabilityStatus': {'status': 'OK'},
      'videoDetails': {
        'videoId': 'vid1',
        'title': 't',
        'isLive': false,
        'thumbnail': {'thumbnails': []},
      },
      'streamingData': {
        'formats': [
          {
            'itag': 18,
            'mimeType': 'video/mp4; codecs="avc1.42001E"',
            'height': 360,
            'signatureCipher':
                'url=https%3A%2F%2Fgv.example%2Fv%3Fn%3DAAAAAAAAAAAAAAAA&s=CIPHERTEXT&sp=sig',
          }
        ],
      },
    };

