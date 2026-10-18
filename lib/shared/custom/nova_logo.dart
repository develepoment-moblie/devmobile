import 'package:flutter/material.dart';

class NovaLogo extends StatelessWidget {
  final double size;
  const NovaLogo({super.key, this.size = 46});

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/nova_paris_logo.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: 'Logo Nova Paris Hôtel',
    filterQuality: FilterQuality.high,
  );
}
