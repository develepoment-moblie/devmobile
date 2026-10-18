import 'package:flutter/material.dart';

import '../models/room.dart';
import '../../shared/custom/app_theme.dart';
import '../../shared/custom/nova_icon.dart';

(Color, Color) roomTone(Room room, {bool cleaning = true}) {
  if (!cleaning) {
    return switch (room.status) {
      RoomStatus.ready => (AppColors.green, AppColors.greenLight),
      RoomStatus.dirty => (AppColors.orange, AppColors.orangeLight),
      RoomStatus.occupied => (AppColors.gray, AppColors.grayLight),
      RoomStatus.maintenance => (AppColors.red, AppColors.redLight),
    };
  }
  return switch (room.cleaning) {
    CleaningStatus.completed => (AppColors.green, AppColors.greenLight),
    CleaningStatus.inProgress ||
    CleaningStatus.review => (AppColors.orange, AppColors.orangeLight),
    CleaningStatus.waiting =>
      room.urgent
          ? (AppColors.red, AppColors.redLight)
          : (AppColors.gray, AppColors.grayLight),
  };
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  final double fontSize;
  final Color? textColor;
  const StatusBadge(
    this.label, {
    super.key,
    required this.color,
    required this.background,
    this.fontSize = 7,
    this.textColor,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: textColor ?? color,
          ),
        ),
      ],
    ),
  );
}

class Roomcard extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;
  final bool cleaning;
  const Roomcard({
    super.key,
    required this.room,
    required this.onTap,
    this.cleaning = true,
  });
  @override
  Widget build(BuildContext context) {
    final (color, background) = roomTone(room, cleaning: cleaning);
    return Semantics(
      button: true,
      label:
          'Chambre ${room.number}, ${cleaning ? room.cleaningLabel : room.statusLabel}',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 47,
                  height: 47,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    room.number,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chambre ${room.number}',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        cleaning
                            ? room.subtitle
                            : '${room.category} · Étage ${room.floor}',
                        style: const TextStyle(
                          fontSize: 7,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                StatusBadge(
                  cleaning ? room.cleaningLabel : room.statusLabel,
                  color: color,
                  background: background,
                ),
                const SizedBox(width: 10),
                const NovaIcon(NovaSymbol.chevron),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
