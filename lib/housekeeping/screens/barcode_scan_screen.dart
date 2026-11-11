import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/product_lookup.dart';
import 'code_scan_screen.dart';

/// Opens the camera on a product's barcode; null when cancelled.
typedef ScanBarcode = Future<String?> Function(BuildContext context);

Future<String?> scanProductBarcode(BuildContext context) =>
    Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );

String? _productCode(String? raw) => isProductBarcode(raw) ? raw : null;

// Scans a product's barcode (EAN-13, EAN-8, UPC); pops with the code.
class BarcodeScanScreen extends StatelessWidget {
  const BarcodeScanScreen({super.key});

  @override
  Widget build(BuildContext context) => const CodeScanScreen(
    title: 'Scanner un produit',
    hint: 'Visez le code-barres imprimé sur le produit.',
    refused: 'Ce code n’est pas un code-barres de produit.',
    permissionDenied: 'Autorisez l’appareil photo pour scanner les produits.',
    formats: [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
    accept: _productCode,
    frame: Size(280, 150),
  );
}
