import 'package:flutter/material.dart';

import 'maintenance_theme.dart';

/// Carte terracotta "MAINTENANCE · N interventions actives".
class MaintenanceSummaryCard extends StatelessWidget {
  final int activeCount;
  const MaintenanceSummaryCard({super.key, required this.activeCount});

  @override
  Widget build(BuildContext context) {
    final label = activeCount <= 1
        ? '$activeCount intervention active'
        : '$activeCount interventions actives';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: MC.maintenanceCard,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: MC.white16,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.build_outlined,
              size: 22,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MAINTENANCE',
                  style: mt(
                    9.5,
                    weight: FontWeight.w700,
                    letterSpacing: 1,
                    color: MC.white65,
                  ),
                ),
                const SizedBox(height: 6),
                Text(label, style: mt(21, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
