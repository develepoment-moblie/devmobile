import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../shared/custom/app_theme.dart';

// The camera screen behind the module's scanners (a room's QR code, a
// product's barcode): pops with the first code [accept] keeps.
class CodeScanScreen extends StatefulWidget {
  final String title, hint, refused, permissionDenied;
  final List<BarcodeFormat> formats;

  /// What to return for a code read, or null to keep looking.
  final String? Function(String? raw) accept;

  /// The aiming frame (a square for QR codes, wider for barcodes).
  final Size frame;
  const CodeScanScreen({
    super.key,
    required this.title,
    required this.hint,
    required this.refused,
    required this.permissionDenied,
    required this.formats,
    required this.accept,
    this.frame = const Size(240, 240),
  });
  @override
  State<CodeScanScreen> createState() => _CodeScanScreenState();
}

class _CodeScanScreenState extends State<CodeScanScreen> {
  late final _controller = MobileScannerController(formats: widget.formats);
  bool _done = false;
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _detect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final value = widget.accept(code.rawValue);
      if (value != null) {
        _done = true;
        Navigator.pop(context, value);
        return;
      }
    }
    setState(() => _message = widget.refused);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: 'Lampe',
          color: Colors.white,
          onPressed: _controller.toggleTorch,
          icon: const Icon(Icons.flashlight_on_outlined),
        ),
      ],
    ),
    body: Stack(
      alignment: Alignment.center,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _detect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? widget.permissionDenied
                    : 'Caméra indisponible.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
        // Aiming frame.
        IgnorePointer(
          child: Container(
            width: widget.frame.width,
            height: widget.frame.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.gold, width: 3),
            ),
          ),
        ),
        Positioned(
          bottom: 48,
          left: 24,
          right: 24,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _message ?? widget.hint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    ),
  );
}
