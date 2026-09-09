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

import '../clients/client_configs.dart';
import '../clients/innertube_client.dart';
import '../models/kmep_models.dart';
import 'comment_parser.dart';

/// Comment extraction. Rides the InnerTube `/next` endpoint with the
/// WEB client — no PO token, no player.js needed.
///
/// Flow (matches what YouTube's own web app does):
///  1. `next` for the videoId -> find the `comment-item-section`'s
///     continuation token (comments are lazy-loaded on the watch page).
///  2. `next` with that token -> page 1 of comments, plus a token for
///     page 2, and so on.
///  3. Each thread carries its own replies continuation token.
///
/// Get one of these from `Kmep.getComments` / `Kmep.getCommentReplies`,
/// or standalone.
class CommentClient {
  final InnerTubeClient _client;

  CommentClient({String hl = 'en', String gl = 'US'})
      : _hl = hl,
        _gl = gl,
        _client = InnerTubeClient(ClientRegistry.resolved('WEB'));

  final String _hl;
  final String _gl;

  /// First page of top-level comment threads for [videoId].
  ///
  /// [sort] picks YouTube's ordering: newest first (`newest`) or the
  /// default "top comments" ordering (`top`). The other ordering is a
  /// different continuation token picked from the same watch-next
  /// response — no extra request.
  Future<CommentsPage> getComments(String videoId,
      {CommentSort sort = CommentSort.top}) async {
    final watchNext = await _client.fetchNext(videoId, hl: _hl, gl: _gl);
    final tokens = findCommentSectionTokens(watchNext);
    if (tokens.isEmpty) {
      throw const KMEPException(
          KMEPErrorCode.commentsUnavailable, 'no comment section found');
    }
    final token =
        sort == CommentSort.newest && tokens.length > 1 ? tokens[1] : tokens[0];
    return getCommentsByContinuation(token);
  }

  /// Fetches a comment page by continuation token (from a previous
  /// [CommentsPage.continuation] — advanced use; prefer `Kmep.getComments`).
  Future<CommentsPage> getCommentsByContinuation(String continuation) async {
    final resp = await _client.fetchNext(
      '', // continuation-запрос не требует videoId
      continuation: continuation,
      hl: _hl,
      gl: _gl,
    );
    return parseCommentsPage(resp);
  }

  /// Replies for one comment thread. [repliesContinuation] comes from
  /// [CommentInfo.repliesContinuation]. Returns the first batch of
  /// replies plus a continuation for more, if any.
  Future<CommentsPage> getReplies(String repliesContinuation) async {
    final resp = await _client.fetchNext(
      '',
      continuation: repliesContinuation,
      hl: _hl,
      gl: _gl,
    );
    return parseCommentsPage(resp);
  }

  void close() => _client.close();
}

enum CommentSort { top, newest }
