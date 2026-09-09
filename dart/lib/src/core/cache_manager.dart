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

abstract class CacheManager {
  Future<VideoInfo?> getVideo(String videoId);
  Future<void> putVideo(String videoId, VideoInfo video,
      {Duration ttl = const Duration(minutes: 10)});

  Future<ChannelInfo?> getChannel(String channelId);
  Future<void> putChannel(String channelId, ChannelInfo channel,
      {Duration ttl = const Duration(hours: 1)});

  Future<void> clear();
}

class InMemoryCacheManager implements CacheManager {
  final _videos = <String, _Entry<VideoInfo>>{};
  final _channels = <String, _Entry<ChannelInfo>>{};

  @override
  Future<VideoInfo?> getVideo(String videoId) async {
    final e = _videos[videoId];
    if (e == null || e.isExpired) return null;
    return e.value;
  }

  @override
  Future<void> putVideo(String videoId, VideoInfo video,
      {Duration ttl = const Duration(minutes: 10)}) async {
    _videos[videoId] = _Entry(video, DateTime.now().add(ttl));
  }

  @override
  Future<ChannelInfo?> getChannel(String channelId) async {
    final e = _channels[channelId];
    if (e == null || e.isExpired) return null;
    return e.value;
  }

  @override
  Future<void> putChannel(String channelId, ChannelInfo channel,
      {Duration ttl = const Duration(hours: 1)}) async {
    _channels[channelId] = _Entry(channel, DateTime.now().add(ttl));
  }

  @override
  Future<void> clear() async {
    _videos.clear();
    _channels.clear();
  }
}

class _Entry<T> {
  final T value;
  final DateTime expiresAt;
  _Entry(this.value, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
