import 'package:flutter/material.dart';

class NovaLogo extends StatelessWidget {
  final double size;

  /// Cream lettering, for dark backgrounds.
  final bool light;
  const NovaLogo({super.key, this.size = 46, this.light = false});

  @override
  Widget build(BuildContext context) => Image.asset(
    light
        ? 'assets/images/nova_paris_logo_light.png'
        : 'assets/images/nova_paris_logo.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: 'Logo Nova Paris Hôtel',
    filterQuality: FilterQuality.high,
  );
}

/// Compact brand for headers: the logo's star and the NOVA PARIS wordmark.
/// The full logo is unreadable below about 100 pixels.
class NovaBrand extends StatelessWidget {
  final bool light;
  const NovaBrand({super.key, this.light = false});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Nova Paris Hôtel',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The star spans x 166-308 and y 96-254 of the 480 px logo; the
        // lettering starts at y 282, so the crop stops above it.
        ClipRect(
          child: Align(
            alignment: const Alignment(-.02, -.42),
            widthFactor: .34,
            heightFactor: .36,
            child: Image.asset(
              light
                  ? 'assets/images/nova_paris_logo_light.png'
                  : 'assets/images/nova_paris_logo.png',
              width: 104,
              height: 104,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'NOVA PARIS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: light ? Colors.white : const Color(0xFF25322F),
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.6,
            ),
          ),
        ),
      ],
    ),
  );
}
