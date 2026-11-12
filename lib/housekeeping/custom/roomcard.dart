import 'package:flutter/material.dart';

import '../models/room.dart';
import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import 'nova_icon.dart';

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
    this.fontSize = 11.5,
    this.textColor,
  });
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.soft,
        ),
        child: PressableScale(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    room.number,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chambre ${room.number}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cleaning
                            ? room.subtitle
                            : '${room.category} · Étage ${room.floor}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      StatusBadge(
                        cleaning ? room.cleaningLabel : room.statusLabel,
                        color: color,
                        background: background,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const NovaIcon(NovaSymbol.chevron),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
