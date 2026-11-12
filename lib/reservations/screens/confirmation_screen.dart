import 'package:flutter/material.dart';
import '../custom/app_colors.dart';
import '../models/reservation.dart';

class ConfirmationScreen extends StatelessWidget {
  final Reservation reservation;
  const ConfirmationScreen({super.key, required this.reservation});

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Confirmation'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            const CircleAvatar(
              radius: 36,
              backgroundColor: Color(0xFFE3EFE8),
              child: Icon(Icons.check, size: 36, color: AppColors.success),
            ),
            const SizedBox(height: 16),
            const Text('Réservation confirmée',
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 8),
            const Text('Paris vous attend.',
                style: TextStyle(fontSize: 28, color: AppColors.navy)),
            const SizedBox(height: 24),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.room.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    _row('Réservation', r.id),
                    _row('Client', r.guestName),
                    _row('Arrivée', fmtDate(r.checkIn)),
                    _row('Départ', fmtDate(r.checkOut)),
                    _row('Voyageurs', '${r.guests}'),
                    const Divider(height: 24),
                    _row('Total', '${r.total.toStringAsFixed(0)} €', bold: true),
                  ],
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.navy,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () =>
                    Navigator.popUntil(context, (route) => route.isFirst),
                child: const Text('Retour à l\'accueil',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: const TextStyle(color: AppColors.muted)),
        Text(v,
            style: TextStyle(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      ],
    ),
  );
}