/// Small local persistence contract. Feature adapters never depend on app/
/// or on the other feature's models and screens.
/// A store that says when a change was saved, whoever made it (a screen,
/// another module's event, a rule run on opening).
abstract interface class ChangeSignal {
  Stream<void> get changes;
}

abstract interface class LocalSessionStore {
  Future<Map<String, dynamic>> readState();
  Future<void> change(void Function(Map<String, dynamic>) action);
  Map<String, dynamic> actor(Map<String, dynamic> state);
  Never fail(String message, [int status = 400]);
}
