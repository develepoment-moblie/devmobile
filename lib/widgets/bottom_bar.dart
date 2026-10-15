import 'package:flutter/material.dart';

// ============ PALETTE (locale au widget) ============
const _kCream     = Color(0xFFF6F1EA);
const _kDarkGreen = Color(0xFF1B3A32);
const _kTerra     = Color(0xFFC4704F);
const _kMuted     = Color(0xFF8B8378);

class BottomBar extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;
  final int? badgeIndex;

  const BottomBar({
    super.key,
    required this.current,
    required this.onTap,
    this.badgeIndex,
  });

  static const _items = [
    (Icons.grid_view_outlined,       Icons.grid_view_rounded, 'Accueil'),
    (Icons.calendar_today_outlined,  Icons.calendar_today,    'Réservations'),
    (Icons.meeting_room_outlined,    Icons.meeting_room,      'Chambres'),
    (Icons.room_service_outlined,    Icons.room_service,      'Services'),
    (Icons.person_outline,           Icons.person,            'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCream,
        border: Border(
          top: BorderSide(color: Colors.black.withOpacity(0.05)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: List.generate(_items.length, (i) {
              final (iconOut, iconFill, label) = _items[i];
              return _BottomItem(
                iconOutlined: iconOut,
                iconFilled: iconFill,
                label: label,
                selected: current == i,
                showBadge: badgeIndex == i,
                onTap: () => onTap(i),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  final IconData iconOutlined;
  final IconData iconFilled;
  final String label;
  final bool selected;
  final bool showBadge;
  final VoidCallback onTap;

  const _BottomItem({
    required this.iconOutlined,
    required this.iconFilled,
    required this.label,
    required this.selected,
    required this.showBadge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? _kDarkGreen : _kMuted;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 26,
              child: Stack(
                alignment: Alignment.topRight,
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(
                      selected ? iconFilled : iconOutlined,
                      size: 22,
                      color: color,
                    ),
                  ),
                  if (showBadge)
                    Positioned(
                      top: 2,
                      right: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: _kTerra,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}