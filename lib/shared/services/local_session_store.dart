/// Small local persistence contract. Feature adapters never depend on app/
/// or on the other feature's models and screens.
abstract interface class LocalSessionStore {
  Future<Map<String, dynamic>> readState();
  Future<void> change(void Function(Map<String, dynamic>) action);
  Map<String, dynamic> actor(Map<String, dynamic> state);
  Never fail(String message, [int status = 400]);
}
