
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/services/evidence_photo.dart';
import '../../shared/services/app_exception.dart';

abstract interface class TaskPhotoPicker {
  Future<Uint8List?> pick({required bool camera});
  Future<Uint8List?> recover();
}

class NativeTaskPhotoPicker implements TaskPhotoPicker {
  final _picker = ImagePicker();
  Future<Uint8List> _read(XFile file) async {
    if (await file.length() > EvidencePhoto.maxInputBytes) {
      throw const AppServiceException('Choisissez une photo de 10 Mo maximum.');
    }
    return EvidencePhoto.prepare(await file.readAsBytes());
  }

  @override
  Future<Uint8List?> pick({required bool camera}) async {
    final file = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 75,
    );
    return file == null ? null : _read(file);
  }

  @override
  Future<Uint8List?> recover() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    final file = response.files?.firstOrNull;
    return file == null ? null : _read(file);
  }
}
