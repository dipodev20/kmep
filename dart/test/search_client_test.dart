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

import 'package:test/test.dart';
import 'package:kmep_proto/kmep.dart';
import 'package:kmep_proto/src/search/search_client.dart';

void main() {
  group('lengthToSeconds', () {
    test('parses mm:ss', () => expect(lengthToSeconds('12:34'), 754));
    test('parses h:mm:ss', () => expect(lengthToSeconds('1:02:03'), 3723));
    test('rejects garbage shape', () => expect(lengthToSeconds('1:2:3:4'), 0));
  });

  group('viewsFromText', () {
    test('strips non-digits',
        () => expect(viewsFromText('1,234,567 views'), 1234567));
    test('empty on no digits', () => expect(viewsFromText('no views yet'), 0));
  });

  group('parseSearchResults', () {
    test('collects videoRenderer nodes and dedupes by id', () {
      final response = {
        'contents': {
          'items': [
            {
              'videoRenderer': {
                'videoId': 'abc123',
                'title': {
                  'runs': [
                    {'text': 'A great video'}
                  ]
                },
                'ownerText': {
                  'runs': [
                    {'text': 'Some Channel'}
                  ]
                },
                'lengthText': {'simpleText': '3:21'},
                'viewCountText': {'simpleText': '4,321 views'},
                'thumbnail': {
                  'thumbnails': [
                    {'url': '//i.ytimg.com/vi/abc123/small.jpg'},
                    {'url': '//i.ytimg.com/vi/abc123/large.jpg'},
                  ],
                },
              },
            },
            // Duplicate of the same video via a different renderer shape —
            // should not produce a second entry.
            {
              'gridVideoRenderer': {'videoId': 'abc123', 'title': {}},
            },
          ],
        },
      };

      final results = parseSearchResults(response);
      expect(results, hasLength(1));
      final r = results.single;
      expect(r.videoId, 'abc123');
      expect(r.title, 'A great video');
      expect(r.channelName, 'Some Channel');
      expect(r.durationSeconds, 201);
      expect(r.viewCount, 4321);
      expect(r.thumbnailUrl, 'https://i.ytimg.com/vi/abc123/large.jpg');
    });

    test('skips renderers with no videoId', () {
      final response = {
        'videoRenderer': {'title': 'no id here'},
      };
      expect(parseSearchResults(response), isEmpty);
    });
  });

  group('CachedWatchPageMetaProvider', () {
    test('only calls the inner provider once within the TTL', () async {
      var calls = 0;
      final inner = _FakeMetaProvider(() {
        calls++;
        return const WatchPageMeta(signatureTimestamp: 1);
      });
      final cached =
          CachedWatchPageMetaProvider(inner, ttl: const Duration(minutes: 5));

      await cached.fetch('vid1');
      await cached.fetch('vid1');
      await cached.fetch('vid1');
      expect(calls, 1);

      // A different video is a cache miss.
      await cached.fetch('vid2');
      expect(calls, 2);
    });

    test('clear() forces a re-fetch', () async {
      var calls = 0;
      final inner = _FakeMetaProvider(() {
        calls++;
        return const WatchPageMeta(signatureTimestamp: 1);
      });
      final cached = CachedWatchPageMetaProvider(inner);

      await cached.fetch('vid1');
      cached.clear();
      await cached.fetch('vid1');
      expect(calls, 2);
    });
  });
}

class _FakeMetaProvider implements WatchPageMetaProvider {
  final WatchPageMeta? Function() _build;
  _FakeMetaProvider(this._build);

  @override
  Future<WatchPageMeta?> fetch(String videoId) async => _build();
}
