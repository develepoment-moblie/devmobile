import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../services/housekeeping_sync.dart';

/// "Synchronisé", "Hors ligne · 2 actions en attente"… Hidden while no
/// server is set.
class SyncBadge extends StatelessWidget {
  final HousekeepingSync sync;

  /// Around the badge, only when it is shown.
  final EdgeInsets padding;
  const SyncBadge({
    super.key,
    required this.sync,
    this.padding = EdgeInsets.zero,
  });

  static (String, IconData, Color, Color)? describe(HousekeepingSync sync) {
    final view = sync.overview;
    if (view == null || view.server == null || sync.phase == SyncPhase.off) {
      return null;
    }
    final pending = view.pending;
    final issues = view.conflicts.length + view.rejected.length;
    final extra = [
      if (pending > 0) pendingText(pending),
      if (issues > 0) conflictText(issues),
    ];
    String label(String head) => [head, ...extra].join(' · ');
    return switch (sync.phase) {
      SyncPhase.offline => (
        label('Hors ligne'),
        Icons.cloud_off_outlined,
        AppColors.red,
        AppColors.redLight,
      ),
      SyncPhase.syncing => (
        'Synchronisation…',
        Icons.sync,
        AppColors.primary,
        AppColors.grayLight,
      ),
      _ when pending > 0 || issues > 0 => (
        extra.join(' · '),
        issues > 0 ? Icons.call_split : Icons.outbox_outlined,
        AppColors.orange,
        AppColors.orangeLight,
      ),
      _ => (
        'Synchronisé',
        Icons.cloud_done_outlined,
        AppColors.green,
        AppColors.greenLight,
      ),
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sync,
    builder: (context, _) {
      final look = describe(sync);
      if (look == null) return const SizedBox.shrink();
      final (text, icon, color, background) = look;
      final badge = Semantics(
        liveRegion: true,
        label: 'Synchronisation : $text',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return Padding(padding: padding, child: badge);
    },
  );
}
