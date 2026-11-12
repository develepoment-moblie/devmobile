import 'package:flutter/material.dart';

import 'maintenance_theme.dart';

/// Bouton "Signaler un problème 📷".
class ReportProblemButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const ReportProblemButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(15);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x59C4705A),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: MC.terra,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Signaler un problème',
                  style: mt(13, weight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.photo_camera_outlined,
                  size: 18,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
