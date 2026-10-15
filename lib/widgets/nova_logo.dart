import 'package:flutter/material.dart';

/// Logo réutilisable de Nova Paris.
///
/// Utilisation :
///   NovaLogo()                       → taille 40, rond
///   NovaLogo(size: 120)              → taille personnalisée
///   NovaLogo(circular: false)        → coins arrondis au lieu de rond
///   NovaLogo(size: 120, circular: false) + texte à côté
class NovaLogo extends StatelessWidget {
  final double size;
  final bool circular;
  const NovaLogo({
    super.key,
    this.size = 40,
    this.circular = true,
  });

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/images/logo.jpg',
      width: size,
      height: size,
      fit: BoxFit.cover,
      // 🛡️ Fallback si l'image ne charge pas
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        color: const Color(0xFF1B3A32),
        alignment: Alignment.center,
        child: Text(
          'N',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    return circular
        ? ClipOval(child: image)
        : ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.2),
      child: image,
    );
  }
}