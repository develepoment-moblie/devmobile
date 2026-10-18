/// Only application composition connects the account store to backup tooling.
abstract interface class BackupRepository {
  Future<Map<String, dynamic>> backupSnapshot();
  Future<void> restoreSnapshot(Map<String, dynamic> state);
}
