import 'package:flutter/material.dart';
import '../models/reservation.dart';
import 'app_colors.dart';

class StatusChip extends StatelessWidget {
  final ReservationStatus status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color color;
    switch (status) {
      case ReservationStatus.confirmed:
        label = 'Confirmée'; color = AppColors.success; break;
      case ReservationStatus.checkedIn:
        label = 'En séjour'; color = AppColors.navy; break;
      case ReservationStatus.checkedOut:
        label = 'Terminée'; color = AppColors.muted; break;
      case ReservationStatus.cancelled:
        label = 'Annulée'; color = AppColors.danger; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}