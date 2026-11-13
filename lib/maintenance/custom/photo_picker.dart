import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'maintenance_theme.dart';

/// Ouvre l'appareil photo (mobile) ou la galerie et renvoie les octets
/// de l'image choisie (ou null si l'utilisateur annule).
Future<Uint8List?> pickInterventionPhoto(BuildContext context) async {
  final canUseCamera =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  ImageSource source = ImageSource.gallery;

  if (canUseCamera) {
    final chosen = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: MC.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: MC.dark),
              title: Text(
                'Appareil photo',
                style: mt(14, weight: FontWeight.w600),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: MC.dark),
              title: Text('Galerie', style: mt(14, weight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null) return null;
    source = chosen;
  }

  try {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1280,
      imageQuality: 75,
    );
    if (picked == null) return null;
    return await picked.readAsBytes();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'ajouter la photo.")),
      );
    }
    return null;
  }
}
