// What an action leaves for the sync with the hotel server. The rules put it
// in the state map; HousekeepingStore saves it in the same transaction as the
// action, so an action is never saved without being queued, nor the reverse.

/// Paths of the Manager's catalog actions (SqliteRoomCatalog), e.g.
/// catalog/create. The other paths are /v1/... (SqliteHousekeeping).
const catalogPathPrefix = 'catalog/';

/// Keys only the store reads; the screens never see them.
const syncStateKeys = ['_syncOutbox', '_syncCursor'];

/// Queues the action just applied, to be sent to the server.
void queueForServer(
  Map<String, dynamic> state,
  String path,
  Map<String, dynamic> body,
  String actorId,
  DateTime appliedAt,
) => (state.putIfAbsent('_syncOutbox', () => <dynamic>[]) as List).add({
  'mutationId': body['mutationId'],
  'path': path,
  'body': body,
  'actorId': actorId,
  'appliedAt': appliedAt.toIso8601String(),
});

/// Marks the server's action [seq] as handled, with the change it made.
void advanceSyncCursor(Map<String, dynamic> state, int seq) =>
    state['_syncCursor'] = seq;
