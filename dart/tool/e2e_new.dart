// Полный e2e новых модулей: каналы, плейлисты, комментарии.
// Запуск: dart run tool/e2e_new.dart
import 'package:kmep/kmep.dart';

Future<void> main() async {
  final channel = ChannelClient(hl: 'en', gl: 'US');

  print('=== getChannel ===');
  final info = await channel.getChannel('UC-lHJZR3Gqxm24_Vd_AJ5Yw');
  print('name=${info.name} handle=${info.handle} subs=${info.subscriberCount}');
  print('videos=${info.videoCount} tabs=${info.tabs}');

  print('\n=== getChannelVideos (pages 1-2) ===');
  final p1 = await channel.getChannelVideos('UC-lHJZR3Gqxm24_Vd_AJ5Yw');
  print('p1=${p1.videos.length} cont=${p1.continuation != null}');
  for (final v in p1.videos.take(2)) {
    print('  ${v.videoId} "${_cut(v.title)}" ${v.durationSeconds}s views=${v.viewCount}');
  }
  final p2 = await channel.getChannelVideos('UC-lHJZR3Gqxm24_Vd_AJ5Yw',
      continuation: p1.continuation);
  print('p2=${p2.videos.length}');

  print('\n=== getPlaylist (pages 1-2) ===');
  final pl = await channel.getPlaylist('PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI');
  print('title="${_cut(pl.title)}" count=${pl.videoCount} owner=${pl.channelName}');
  print('p1=${pl.videos.length} cont=${pl.continuation != null}');
  final pn = await channel.getPlaylistVideos(
      'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI', pl.continuation!);
  print('p2=${pn.videos.length} cont=${pn.continuation != null}');
  channel.close();

  print('\n=== getComments (top) ===');
  final comments = CommentClient(hl: 'en', gl: 'US');
  final cp = await comments.getComments('dQw4w9WgXcQ');
  print('items=${cp.items.length} cont=${cp.continuation != null}');
  for (final c in cp.items.take(3)) {
    print('  [${c.authorName}] "${_cut(c.text)}" likes=${c.likeCount} '
        'replies=${c.replyCount} pinned=${c.isPinned} heart=${c.isHearted} '
        'repliesCont=${c.repliesContinuation != null}');
  }
  final withR = cp.items.firstWhere((c) => c.repliesContinuation != null);
  print('--- replies of [${withR.authorName}] ---');
  final rp = await comments.getReplies(withR.repliesContinuation!);
  print('replies=${rp.items.length} cont=${rp.continuation != null}');
  for (final r in rp.items.take(3)) {
    print('  [${r.authorName}] "${_cut(r.text)}" likes=${r.likeCount}');
  }
  print('--- comments page 2 ---');
  final cp2 = await comments.getCommentsByContinuation(cp.continuation!);
  print('items=${cp2.items.length} cont=${cp2.continuation != null}');
  print('\n=== getComments (newest) ===');
  final cn = await comments.getComments('dQw4w9WgXcQ',
      sort: CommentSort.newest);
  print('items=${cn.items.length}');
  comments.close();
}

String _cut(String s) => s.length > 45 ? '${s.substring(0, 45)}...' : s;
