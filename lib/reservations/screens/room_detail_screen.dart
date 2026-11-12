import 'package:flutter/material.dart';

import '../custom/app_colors.dart';
import '../models/room.dart';
import '../services/reservation_service.dart';
import 'confirmation_screen.dart';

class RoomDetailScreen extends StatefulWidget {
  final Room room;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;

  const RoomDetailScreen({
    super.key,
    required this.room,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
  });

  @override
  State<RoomDetailScreen> createState() =>
      _RoomDetailScreenState();
}

class _RoomDetailScreenState
    extends State<RoomDetailScreen> {
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _book() {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
          Text('Veuillez saisir le nom du client.'),
        ),
      );
      return;
    }

    try {
      final reservation =
      ReservationService.instance.create(
        room: widget.room,
        guestName: _nameCtrl.text.trim(),
        checkIn: widget.checkIn,
        checkOut: widget.checkOut,
        guests: widget.guests,
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ConfirmationScreen(
            reservation: reservation,
          ),
        ),
      );
    } on StateError catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nights =
        widget.checkOut.difference(widget.checkIn).inDays;

    final total =
        nights * widget.room.pricePerNight;

    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: AppBar(
        title: const Text('Détail chambre'),
      ),

      body: ListView(
        padding: const EdgeInsets.all(20),

        children: [
          // ROOM IMAGE
          ClipRRect(
            borderRadius: BorderRadius.circular(20),

            child: Image.asset(
              widget.room.imagePath,

              height: 220,
              width: double.infinity,

              fit: BoxFit.cover,

              errorBuilder:
                  (context, error, stackTrace) {
                debugPrint(
                  'DETAIL IMAGE ERROR: '
                      '${widget.room.imagePath}',
                );

                debugPrint(
                  'ERROR: $error',
                );

                return Container(
                  height: 220,
                  width: double.infinity,
                  color:
                  AppColors.navy.withValues(alpha: 0.08),

                  child: Column(
                    mainAxisAlignment:
                    MainAxisAlignment.center,

                    children: [
                      const Icon(
                        Icons.broken_image_outlined,
                        size: 60,
                        color: AppColors.navy,
                      ),

                      const SizedBox(height: 8),

                      Text(
                        widget.room.imagePath,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          Text(
            widget.room.name,
            style: const TextStyle(
              fontSize: 26,
              color: AppColors.navy,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            widget.room.description,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 15,
            ),
          ),

          const SizedBox(height: 20),

          Row(
            mainAxisAlignment:
            MainAxisAlignment.spaceAround,

            children: [
              _info(
                Icons.people_outline,
                '${widget.room.capacity} pers.',
              ),

              _info(
                Icons.square_foot,
                '${widget.room.surface} m²',
              ),

              _info(
                Icons.sell_outlined,
                '${widget.room.pricePerNight.toStringAsFixed(0)} €/nuit',
              ),
            ],
          ),

          const Divider(height: 40),

          Text(
            'Séjour du ${fmtDate(widget.checkIn)} '
                'au ${fmtDate(widget.checkOut)}',

            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            '$nights nuit(s) · '
                '${widget.guests} voyageur(s)',

            style: const TextStyle(
              color: AppColors.muted,
            ),
          ),

          const SizedBox(height: 20),

          TextField(
            controller: _nameCtrl,

            textCapitalization:
            TextCapitalization.words,

            decoration: InputDecoration(
              labelText: 'Nom du client',

              filled: true,
              fillColor: Colors.white,

              border: OutlineInputBorder(
                borderRadius:
                BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 24),

          Row(
            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,

            children: [
              const Text(
                'Total',
                style: TextStyle(fontSize: 16),
              ),

              Text(
                '${total.toStringAsFixed(0)} €',

                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          SizedBox(
            height: 52,
            width: double.infinity,

            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                AppColors.gold,

                foregroundColor:
                AppColors.navy,

                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(16),
                ),
              ),

              onPressed: _book,

              child: const Text(
                'Réserver',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(
      IconData icon,
      String text,
      ) {
    return Column(
      children: [
        Icon(
          icon,
          color: AppColors.navy,
        ),

        const SizedBox(height: 4),

        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}