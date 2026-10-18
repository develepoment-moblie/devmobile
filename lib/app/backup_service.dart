import 'dart:typed_data';

import '../shared/services/backup_codec.dart';
import '../shared/services/backup_repository.dart';

abstract interface class BackupService {
  Future<Uint8List> create(String password);
  Future<BackupContents> inspect(Uint8List bytes, String password);
  Future<void> restore(BackupContents contents);
}

class LocalBackupService implements BackupService {
  final BackupRepository repository;
  LocalBackupService(this.repository);

  @override
  Future<Uint8List> create(String password) async =>
      BackupCodec.encode(await repository.backupSnapshot(), password);
  @override
  Future<BackupContents> inspect(Uint8List bytes, String password) =>
      BackupCodec.decode(bytes, password);
  @override
  Future<void> restore(BackupContents contents) =>
      repository.restoreSnapshot(contents.state);
}
