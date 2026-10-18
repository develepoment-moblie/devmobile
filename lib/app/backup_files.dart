import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../shared/services/app_exception.dart';
import '../shared/services/backup_codec.dart';

class BackupFile {
  final String name;
  final Uint8List bytes;
  const BackupFile(this.name, this.bytes);
}

abstract interface class BackupFiles {
  Future<bool> save(String name, Uint8List bytes);
  Future<BackupFile?> pick();
}

/// Android's document picker writes outside app storage without broad permissions.
class NativeBackupFiles implements BackupFiles {
  @override
  Future<bool> save(String name, Uint8List bytes) async =>
      await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        dialogTitle: 'Enregistrer la sauvegarde',
      ) !=
      null;

  @override
  Future<BackupFile?> pick() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choisir une sauvegarde Nova Paris',
    );
    if (file == null) return null;
    final length = await file.length();
    if (length != null && length > BackupCodec.maxBytes) {
      throw const AppServiceException(
        'Choisissez une sauvegarde de 64 Mo maximum.',
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      if (builder.length + chunk.length > BackupCodec.maxBytes) {
        throw const AppServiceException(
          'Choisissez une sauvegarde de 64 Mo maximum.',
        );
      }
      builder.add(chunk);
    }
    return BackupFile(file.name, builder.takeBytes());
  }
}
