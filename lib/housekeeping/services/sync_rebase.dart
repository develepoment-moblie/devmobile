import 'dart:convert';

import 'app_exception.dart';
import 'local_session_store.dart';
import 'room_catalog_backend.dart';
import 'sqlite_housekeeping.dart';
import 'sqlite_room_catalog.dart';
import 'sync_outbox.dart';

// The server's order decides. Every phone keeps two versions of the data:
//  - the confirmed version: every action the server numbered, applied in its
//    order through the module's rules. Same starting data + same actions in
//    the same order + deterministic rules (ids and times come from each
//    action, see inMutation) = the same result on every phone;
//  - what the screens show: the confirmed version, plus this phone's actions
//    the server has not numbered yet, applied again on top.
// When new numbered actions arrive, [rebase] moves the confirmed version
// forward and rebuilds what the screens show. An action the rules refuse is
// refused on every phone alike; when it was this phone's, it disappears from
// the screens and is listed in "Vos actions refusées". Like `git rebase`.

/// An action as the server numbered it.
class SyncAction {
  final int? seq;
  final String mutationId, path, actorId;
  final Map<String, dynamic> body;
  final DateTime appliedAt;
  const SyncAction({
    this.seq,
    required this.mutationId,
    required this.path,
    required this.actorId,
    required this.body,
    required this.appliedAt,
  });

  /// From the server's JSON (GET /v1/sync/pull).
  factory SyncAction.fromJson(Map<String, dynamic> m) => SyncAction(
    seq: m['seq'] as int,
    mutationId: m['mutationId'] as String,
    path: m['path'] as String,
    actorId: m['actorId'] as String,
    body: (m['body'] as Map).cast<String, dynamic>(),
    appliedAt: DateTime.tryParse('${m['appliedAt']}') ?? DateTime(2000),
  );
}

/// A numbered action the rules refused.
class SyncRefusal {
  final SyncAction action;
  final String message;
  final int status;
  const SyncRefusal(this.action, this.message, this.status);
}

class RebaseResult {
  /// The new confirmed version and its last server number.
  final Map<String, dynamic> base;
  final int seq;

  /// What the screens show: [base] + this phone's actions still waiting.
  final Map<String, dynamic> current;

  /// Numbered actions handled (applied or refused): they leave the queue.
  final Set<String> confirmed;
  final List<SyncRefusal> refused;
  const RebaseResult({
    required this.base,
    required this.seq,
    required this.current,
    required this.confirmed,
    required this.refused,
  });
}

/// Applies [numbered] (server order) to [base], then [waiting] (this phone's
/// actions not numbered yet) on a copy. [authors] maps an account id to the
/// actor the rules expect ({id, full_name, role}); [users] is the staff list
/// the rules read. [until] is the last server number looked at.
Future<RebaseResult> rebase({
  required Map<String, dynamic> base,
  required int seq,
  required List<SyncAction> numbered,
  required List<SyncAction> waiting,
  required Map<String, Map<String, dynamic>> authors,
  required Object? users,
  required int until,
}) async {
  final confirmed = _copy(base)..['users'] = users;
  var last = seq;
  final handled = <String>{};
  final refused = <SyncRefusal>[];
  for (final action in numbered) {
    if (action.seq != null && action.seq! <= seq) continue;
    handled.add(action.mutationId);
    final error = await _apply(confirmed, action, authors);
    if (error != null) refused.add(error);
    if (action.seq != null && action.seq! > last) last = action.seq!;
  }
  if (until > last) last = until;
  final current = _copy(confirmed);
  // Photos are written once, from both versions.
  current['_photoWrites'] = {...?confirmed['_photoWrites'] as Map?};
  for (final action in waiting) {
    if (handled.contains(action.mutationId)) continue;
    // Refused here too: it will be refused in the server's order as well,
    // which reports it; until then it changes nothing.
    await _apply(current, action, authors);
  }
  return RebaseResult(
    base: confirmed,
    seq: last,
    current: current,
    confirmed: handled,
    refused: refused,
  );
}

Map<String, dynamic> _copy(Map<String, dynamic> state) =>
    (jsonDecode(jsonEncode(state)) as Map).cast<String, dynamic>();

// Runs [action] through the module's rules on [state], as its author, at
// its own time. Returns the refusal, or null once applied.
Future<SyncRefusal?> _apply(
  Map<String, dynamic> state,
  SyncAction action,
  Map<String, Map<String, dynamic>> authors,
) async {
  final author = authors[action.actorId];
  if (author == null) {
    return SyncRefusal(action, 'Auteur inconnu sur ce téléphone.', 403);
  }
  final store = _StateStore(state, author);
  try {
    if (action.path.startsWith(catalogPathPrefix)) {
      final name = action.path.substring(catalogPathPrefix.length);
      final kind = RoomCatalogAction.values.asNameMap()[name];
      if (kind == null) return SyncRefusal(action, 'Action inconnue.', 400);
      await SqliteRoomCatalog(
        store,
        clock: () => action.appliedAt,
        queueForSync: false,
      ).mutate(kind, action.body);
    } else {
      await SqliteHousekeeping(
        store,
        clock: () => action.appliedAt,
        queueForSync: false,
      ).mutate(action.path, action.body);
    }
    return null;
  } on AppServiceException catch (e) {
    return SyncRefusal(action, e.message, e.status ?? 400);
  } on TypeError {
    return SyncRefusal(action, 'Action illisible.', 400);
  }
}

/// The rules' store, on a state in memory, as one author. A refused action
/// leaves the state as it was (the change runs on a copy).
class _StateStore implements LocalSessionStore {
  final Map<String, dynamic> state;
  final Map<String, dynamic> author;
  _StateStore(this.state, this.author);

  @override
  Map<String, dynamic> actor(Map<String, dynamic> state) => author;

  @override
  Future<void> change(void Function(Map<String, dynamic>) action) async {
    final photos = state.remove('_photoWrites') as Map?;
    final draft = _copy(state);
    if (photos != null) state['_photoWrites'] = photos;
    action(draft);
    final written = draft.remove('_photoWrites') as Map?;
    state
      ..clear()
      ..addAll(draft)
      ..['_photoWrites'] = {...?photos, ...?written};
  }

  @override
  Never fail(String message, [int status = 400]) =>
      throw AppServiceException(message, status);

  @override
  Future<Map<String, dynamic>> readState() async => _copy(state);
}
