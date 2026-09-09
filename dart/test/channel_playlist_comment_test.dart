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
import 'dart:io';

import 'package:test/test.dart';
import 'package:kmep/kmep.dart';

void main() {
  group('ChannelClient parsing', () {
    test('parses channel header: name, handle, subs, tabs', () {
      final resp = _load('channel_fixture.json');
      final info = ChannelParseAccess.parseHeaderForTest(resp);
      expect(info, isNotNull);
      expect(info!.name, 'PewDiePie');
      expect(info.handle, '@PewDiePie');
      expect(info.subscriberCount, greaterThan(0));
      expect(info.videoCount, greaterThan(0));
      expect(info.tabs, contains('Videos'));
      expect(info.avatars, isNotEmpty);
      expect(info.banner, isNotNull);
    });

    test('parses channel videos page: lockupViewModel cards', () {
      final resp = _load('channel_fixture.json');
      final page = ChannelParseAccess.parseVideosForTest(resp);
      expect(page.videos, isNotEmpty);
      final v = page.videos.first;
      expect(v.videoId, isNotEmpty);
      expect(v.title, isNotEmpty);
      expect(v.durationSeconds, greaterThan(0));
      expect(page.continuation, isNotNull);
    });
  });

  group('CommentParser', () {
    test('parses a comment page: author, text, likes, replies token', () {
      final resp = _load('comments_fixture.json');
      final page = parseCommentsPage(resp);
      expect(page.items, isNotEmpty);
      final c = page.items.first;
      expect(c.authorName, '@YouTube');
      expect(c.text, 'can confirm: he never gave us up');
      expect(c.likeCount, greaterThan(0));
      expect(c.replyCount, greaterThan(0));
      expect(c.isPinned, isTrue);
      expect(c.isHearted, isTrue);
      expect(c.isVerifiedAuthor, isTrue);
      expect(c.repliesContinuation, isNotNull);
      expect(c.publishedTime, isNotNull);
    });

    test('unwraps nested {commentViewModel:{...}} shape', () {
      // A/B-флат: vm может прийти обёрнутым ещё раз.
      final resp = _load('comments_fixture.json');
      final nested = <String, dynamic>{
        'onResponseReceivedEndpoints': [
          {
            'reloadContinuationItemsCommand': {
              'slot': 'RELOAD_CONTINUATION_SLOT_BODY',
              'continuationItems': [
                {
                  'commentThreadRenderer': {
                    'commentViewModel': {
                      'commentViewModel': {
                        'commentId': 'C1',
                        'pinnedText': null,
                      }
                    },
                  }
                },
              ],
            }
          },
        ],
        'frameworkUpdates': {
          'entityBatchUpdate': {
            'mutations': [
              {
                'payload': {
                  'commentEntityPayload': {
                    'key': 'k1',
                    'properties': {
                      'commentId': 'C1',
                      'content': {'content': 'nested!'},
                      'publishedTime': '2 days ago',
                    },
                    'author': {
                      'channelId': 'UCx',
                      'displayName': '@someone',
                      'avatarThumbnailUrl': 'http://x/y.jpg',
                    },
                    'toolbar': {
                      'likeCountLiked': '12',
                      'replyCount': '3',
                    },
                  }
                }
              },
            ],
          },
        },
      };
      // ignore: unused_local_variable
      final _ = resp; // fixture не нужен для этого теста
      final page = parseCommentsPage(nested);
      expect(page.items, hasLength(1));
      expect(page.items.first.commentId, 'C1');
      expect(page.items.first.text, 'nested!');
      expect(page.items.first.likeCount, 12);
      expect(page.items.first.replyCount, 3);
    });

    test('findCommentSectionTokens finds the comment-item-section tokens', () {
      final watchNext = {
        'contents': {
          'twoColumnWatchNextResults': {
            'results': {
              'results': {
                'contents': [
                  {
                    'itemSectionRenderer': {
                      'sectionIdentifier': 'comment-item-section',
                      'contents': [
                        {
                          'continuationItemRenderer': {
                            'continuationEndpoint': {
                              'continuationCommand': {'token': 'TOK1'}
                            }
                          }
                        }
                      ],
                    }
                  },
                ],
              },
            },
          },
        },
      };
      final tokens =
          findCommentSectionTokens(watchNext.cast<String, dynamic>());
      expect(tokens, contains('TOK1'));
    });
  });

  group('Playlist parsing', () {
    test(
        'parses playlist header + videos + picks the FIRST continuation '
        '(the trailing one is a signal-only stub)', () {
      final videoLockup = _load('channel_fixture.json')['contents']
                  ['twoColumnBrowseResultsRenderer']['tabs'][0]['tabRenderer']
              ['content']['richGridRenderer']['contents'][0]['richItemRenderer']
          ['content']['lockupViewModel'];
      final resp = <String, dynamic>{
        'header': {
          'pageHeaderRenderer': {
            'content': {
              'pageHeaderViewModel': {
                'title': {
                  'dynamicTextViewModel': {
                    'text': {'content': 'My Playlist'}
                  }
                },
                'metadata': {
                  'contentMetadataViewModel': {
                    'metadataRows': [
                      {
                        'metadataParts': [
                          {
                            'text': {'content': '12 videos'}
                          },
                        ]
                      },
                      {
                        'metadataParts': [
                          {
                            'text': {'content': '1000 views'}
                          },
                        ]
                      },
                    ],
                  },
                },
              },
            },
          },
        },
        'contents': {
          'twoColumnBrowseResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'selected': true,
                  'content': {
                    'sectionListRenderer': {
                      'contents': [
                        {
                          'itemSectionRenderer': {
                            'contents': [
                              {
                                'lockupViewModel': Map<String, dynamic>.from(
                                    videoLockup as Map)
                              },
                              {
                                'continuationItemRenderer': {
                                  'continuationEndpoint': {
                                    'continuationCommand': {'token': 'REAL'}
                                  }
                                }
                              },
                            ],
                          }
                        },
                        {
                          'continuationItemRenderer': {
                            'continuationEndpoint': {
                              'continuationCommand': {'token': 'STUB'}
                            }
                          }
                        },
                      ],
                    },
                  },
                }
              },
            ],
          },
        },
      };
      final page = ChannelParseAccess.parsePlaylistForTest('PL123', resp);
      expect(page.title, 'My Playlist');
      expect(page.videoCount, 12);
      expect(page.videos, isNotEmpty);
      expect(page.continuation, 'REAL', reason: 'не сигнальный STUB-токен');
    });
  });
}

Map<String, dynamic> _load(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

/// Тестовый доступ к приватным парсерам ChannelClient.
class ChannelParseAccess {
  static ChannelInfo? parseHeaderForTest(Map<String, dynamic> resp) {
    final c = ChannelClient(hl: 'en', gl: 'US');
    try {
      return c.testParseChannelHeader(resp);
    } finally {
      c.close();
    }
  }

  static ChannelVideosPage parseVideosForTest(Map<String, dynamic> resp) {
    final c = ChannelClient(hl: 'en', gl: 'US');
    try {
      return c.testParseChannelVideos(resp);
    } finally {
      c.close();
    }
  }

  static PlaylistInfo parsePlaylistForTest(
      String id, Map<String, dynamic> resp) {
    final c = ChannelClient(hl: 'en', gl: 'US');
    try {
      return c.testParsePlaylist(id, resp);
    } finally {
      c.close();
    }
  }
}
