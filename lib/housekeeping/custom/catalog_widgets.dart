import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../models/catalog_data.dart';
import '../models/room.dart';
import 'roomcard.dart';

/// One coloured segment per status, proportional to the room counts.
class StatusBar extends StatelessWidget {
  final RoomCounts counts;
  final double height;
  const StatusBar(this.counts, {super.key, this.height = 10});

  @override
  Widget build(BuildContext context) {
    final parts = [
      (counts.ready, AppColors.green),
      (counts.toClean, AppColors.orange),
      (counts.occupied, AppColors.gray),
      (counts.maintenance, AppColors.red),
    ];
    return Semantics(
      label:
          '${counts.ready} libres, ${counts.toClean} à nettoyer, ${counts.occupied} occupées, ${counts.maintenance} en maintenance',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, grow, _) => ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: SizedBox(
            height: height,
            child: counts.total == 0
                ? const ColoredBox(color: AppColors.grayLight)
                : Row(
                    children: [
                      for (final (count, color) in parts)
                        if (count > 0)
                          Expanded(
                            flex: (count * 1000 * grow).round().clamp(
                              1,
                              1 << 30,
                            ),
                            child: ColoredBox(color: color),
                          ),
                      if (grow < 1)
                        Expanded(
                          flex: ((1 - grow) * counts.total * 1000)
                              .round()
                              .clamp(1, 1 << 30),
                          child: const ColoredBox(color: AppColors.grayLight),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Small legend with the counts behind a [StatusBar].
class StatusLegend extends StatelessWidget {
  final RoomCounts counts;
  const StatusLegend(this.counts, {super.key});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 6,
    children: [
      for (final (label, count, color) in [
        ('Libres', counts.ready, AppColors.green),
        ('À nettoyer', counts.toClean, AppColors.orange),
        ('Occupées', counts.occupied, AppColors.gray),
        ('Maintenance', counts.maintenance, AppColors.red),
      ])
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              '$label $count',
              style: const TextStyle(fontSize: 12, color: AppColors.ink),
            ),
          ],
        ),
    ],
  );
}

/// Square room tile for a floor's grid.
class RoomTile extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;
  const RoomTile({super.key, required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (color, background) = roomTone(room, cleaning: false);
    return Semantics(
      button: true,
      label: 'Chambre ${room.number}, ${room.statusLabel}, ${room.category}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: .35)),
          boxShadow: AppShadows.soft,
        ),
        child: PressableScale(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      room.number,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  room.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    room.statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
