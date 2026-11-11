import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../custom/room_qr.dart';
import 'code_scan_screen.dart';

// Scans a room's door code; pops with the room number.
class QrScanScreen extends StatelessWidget {
  const QrScanScreen({super.key});

  @override
  Widget build(BuildContext context) => const CodeScanScreen(
    title: 'Scanner une chambre',
    hint: 'Visez le QR code collé sur la porte de la chambre.',
    refused: 'Ce code n’est pas un QR code de chambre.',
    permissionDenied: 'Autorisez l’appareil photo pour scanner les chambres.',
    formats: [BarcodeFormat.qrCode],
    accept: roomFromQr,
  );
}
