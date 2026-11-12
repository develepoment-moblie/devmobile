import 'package:flutter/material.dart';

import '../../shared/custom/nova_logo.dart';
import 'maintenance_theme.dart';

/// En-tête du module :
///  - sans [backTitle] : logo + "NOVA PARIS" + cloche (écran principal / onglet)
///  - avec [backTitle] : bouton retour + titre centré + cloche (écrans empilés)
class MaintenanceHeader extends StatelessWidget {
  final String? backTitle;
  const MaintenanceHeader({super.key, this.backTitle});

  @override
  Widget build(BuildContext context) {
    if (backTitle != null) {
      return Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.maybePop(context),
            child: _squareButton(
              const Icon(Icons.chevron_left_rounded, size: 24, color: MC.text),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(backTitle!, style: mt(15, weight: FontWeight.w700)),
            ),
          ),
          const _Bell(),
        ],
      );
    }

    return Row(
      children: [
        const NovaLogo(size: 36),
        const SizedBox(width: 12),
        Text(
          'NOVA PARIS',
          style: mt(13, weight: FontWeight.w700, letterSpacing: 1.3),
        ),
        const Spacer(),
        const _Bell(),
      ],
    );
  }
}

Widget _squareButton(Widget child) => Container(
  width: 40,
  height: 40,
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: MC.border),
  ),
  child: child,
);

class _Bell extends StatelessWidget {
  const _Bell();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _squareButton(
          const Icon(
            Icons.notifications_none_rounded,
            size: 21,
            color: MC.text,
          ),
        ),
        Positioned(
          top: 8,
          right: 9,
          child: Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: MC.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}
