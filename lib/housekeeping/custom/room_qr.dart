import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../shared/custom/app_theme.dart';

/// Content of a room's QR code, for example "novaparis:room:305".
String roomQrData(String number) => 'novaparis:room:$number';

/// The room number in a scanned code, or null for any other code.
String? roomFromQr(String? data) {
  final match = RegExp(r'^novaparis:room:([1-9][0-9]{2})$')
      .firstMatch(data?.trim() ?? '');
  return match?.group(1);
}

// Shows the code to print and stick on the room door.
class RoomQrDialog extends StatelessWidget {
  final String number;
  final String category;
  const RoomQrDialog({super.key, required this.number, required this.category});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('QR code · chambre $number'),
    content: SizedBox(
      width: 260,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: QrImageView(
              data: roomQrData(number),
              size: 210,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppColors.primary,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.primary,
              ),
              semanticsLabel: 'QR code de la chambre $number',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Chambre $number · $category',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'À coller sur la porte : l’agent le scanne pour ouvrir la chambre.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fermer'),
      ),
    ],
  );
}
