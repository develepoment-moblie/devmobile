import 'package:flutter/material.dart';

import '../../../models/intervention.dart';
import '../maintenance_theme.dart';
import 'status_badge.dart';

/// Carte blanche d'une intervention (icône teintée, titre, sous-titre, badge).
class InterventionCard extends StatelessWidget {
  final Intervention intervention;
  final VoidCallback? onTap;

  const InterventionCard({super.key, required this.intervention, this.onTap});

  @override
  Widget build(BuildContext context) {
    final i = intervention;
    // Résolue : badge vert "Résolue" ; sinon badge de priorité.
    final bg = i.isResolved ? i.status.background : i.priority.background;
    final fg = i.isResolved ? i.status.foreground : i.priority.foreground;
    final label = i.isResolved ? i.status.label : i.priority.label;
    final radius = BorderRadius.circular(16);

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: MC.border),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.build_outlined, size: 19, color: fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mt(13, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      i.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mt(10, color: MC.subtitle),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(label: label, background: bg, foreground: fg),
            ],
          ),
        ),
      ),
    );
  }
}
