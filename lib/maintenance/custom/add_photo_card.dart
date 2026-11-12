import 'package:flutter/material.dart';

import 'maintenance_theme.dart';
import 'dashed_border.dart';

/// Carte à bordure pointillée "Ajouter une photo / Documenter le problème".
class AddPhotoCard extends StatelessWidget {
  final VoidCallback? onTap;
  const AddPhotoCard({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DashedBorder(
        color: MC.dashed,
        radius: 16,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Row(
            children: [
              const Icon(Icons.photo_camera_outlined, size: 24, color: MC.dark),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ajouter une photo',
                    style: mt(12, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Documenter le problème',
                    style: mt(10, color: MC.muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
