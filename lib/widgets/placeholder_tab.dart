import 'package:flutter/material.dart';

const _kCream     = Color(0xFFF6F1EA);
const _kDarkGreen = Color(0xFF1B3A32);
const _kMuted     = Color(0xFF8B8378);

/// Écran d'attente réutilisable pour les onglets non développés.
class PlaceholderTab extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const PlaceholderTab({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = 'Bientôt disponible',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: _kCream,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: _kDarkGreen),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _kDarkGreen,
            ),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: _kMuted)),
        ],
      ),
    );
  }
}