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

import '../models/kmep_models.dart';

/// Разбирает сырой playerResponse (JSON от /youtubei/v1/player) в VideoInfo.
/// Потоки здесь ещё "сырые" — url может быть подписан (signatureCipher) или
/// содержать n-sig параметр; расшифровка — забота StreamResolver, не парсера.
class PlayerParser {
  static VideoInfo parse(Map<String, dynamic> response,
      {required String fallbackVideoId}) {
    final playabilityStatus =
        response['playabilityStatus'] as Map<String, dynamic>?;
    final status = playabilityStatus?['status'] as String?;

    if (status == 'ERROR' || status == 'LOGIN_REQUIRED') {
      throw KMEPException(
        KMEPErrorCode.unavailable,
        playabilityStatus?['reason']?.toString() ??
            'Video unavailable ($status)',
      );
    }

    final videoDetails =
        response['videoDetails'] as Map<String, dynamic>? ?? {};
    final microformat = (response['microformat']
            as Map<String, dynamic>?)?['playerMicroformatRenderer']
        as Map<String, dynamic>?;

    final streamingData = response['streamingData'] as Map<String, dynamic>?;
    final isLive =
        videoDetails['isLive'] == true || videoDetails['isLiveContent'] == true;

    final rawStreams = <Map<String, dynamic>>[
      ...?(streamingData?['formats'] as List?)?.cast<Map<String, dynamic>>(),
      ...?(streamingData?['adaptiveFormats'] as List?)
          ?.cast<Map<String, dynamic>>(),
    ];

    final streams = <KMEPStream>[];
    for (final fmt in rawStreams) {
      final url = fmt['url'] as String?;
      // Форматы без url (cipher до резолва, SABR-дескрипторы) не являются
      // проигрываемыми — не превращаем их в стримы с пустым url, иначе
      // оркестратор посчитает такой ответ успехом. Сырьё доступно через
      // rawFormats().
      if (url == null) continue;
      final mimeType = fmt['mimeType'] as String? ?? '';
      final isAudio = mimeType.startsWith('audio/');
      streams.add(KMEPStream(
        url: url,
        quality:
            (fmt['qualityLabel'] as String?) ?? (isAudio ? 'audio' : 'unknown'),
        codec: _extractCodec(mimeType),
        type: isAudio ? 'audio' : 'video',
        itag: (fmt['itag'] as num?)?.toInt() ?? 0,
        width: (fmt['width'] as num?)?.toInt(),
        height: (fmt['height'] as num?)?.toInt(),
        bitrate: (fmt['bitrate'] as num?)?.toInt(),
        mimeType: mimeType,
      ));
    }

    final hlsManifestUrl = streamingData?['hlsManifestUrl'] as String?;
    if (isLive && hlsManifestUrl != null) {
      streams.add(KMEPStream(
        url: hlsManifestUrl,
        quality: 'adaptive',
        codec: 'hls',
        type: 'hls',
        itag: 0,
        mimeType: 'application/x-mpegURL',
        isLive: true,
      ));
    }

    final thumbnails = <String>[
      ...?(videoDetails['thumbnail']?['thumbnails'] as List?)
          ?.map((t) => t['url'] as String?)
          .whereType<String>(),
    ];

    return VideoInfo(
      videoId: (videoDetails['videoId'] as String?) ?? fallbackVideoId,
      title: (videoDetails['title'] as String?) ?? '',
      description: (videoDetails['shortDescription'] as String?) ?? '',
      durationSeconds:
          int.tryParse(videoDetails['lengthSeconds']?.toString() ?? '') ?? 0,
      viewCount: int.tryParse(videoDetails['viewCount']?.toString() ?? '') ?? 0,
      publishDate: microformat?['publishDate'] as String?,
      channelId: (videoDetails['channelId'] as String?) ?? '',
      channelName: (videoDetails['author'] as String?) ?? '',
      channelAvatar: null,
      thumbnails: thumbnails,
      tags: ((videoDetails['keywords'] as List?)?.cast<String>()) ?? const [],
      category: microformat?['category'] as String?,
      isLive: isLive,
      streams: streams,
      hlsManifestUrl: hlsManifestUrl,
    );
  }

  static List<Map<String, dynamic>> rawFormats(Map<String, dynamic> response) {
    final streamingData = response['streamingData'] as Map<String, dynamic>?;
    return <Map<String, dynamic>>[
      ...?(streamingData?['formats'] as List?)?.cast<Map<String, dynamic>>(),
      ...?(streamingData?['adaptiveFormats'] as List?)
          ?.cast<Map<String, dynamic>>(),
    ];
  }

  static String _extractCodec(String mimeType) {
    final match = RegExp('codecs="([^"]+)"').firstMatch(mimeType);
    return match?.group(1) ?? 'unknown';
  }
}
