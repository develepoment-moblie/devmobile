import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../screens/barcode_scan_screen.dart';
import '../services/product_lookup.dart';

// "Scanner le code-barres" in a stock form: opens the camera, looks the code
// up in [sources] (Open Beauty Facts, Open Food Facts) and hands the product
// to [onFound]; unknown or unreachable, the form stays manual. Used by the
// stock form (amenities first) and the minibar menu (food).
class ProductScan extends StatefulWidget {
  final List<ProductSource> sources;

  /// The form disables its fields while the lookup runs.
  final bool enabled;
  final ValueChanged<bool> onBusy;
  final ValueChanged<ProductInfo> onFound;

  /// Replaceable in tests (no camera, no network).
  final ScanBarcode scan;
  final ProductLookup? lookup;
  const ProductScan({
    super.key,
    required this.sources,
    required this.onFound,
    required this.onBusy,
    this.enabled = true,
    this.scan = scanProductBarcode,
    this.lookup,
  });
  @override
  State<ProductScan> createState() => _ProductScanState();
}

class _ProductScanState extends State<ProductScan> {
  late final _lookup = widget.lookup ?? ProductLookup();
  bool _busy = false;
  String? _note, _error;
  ProductInfo? _found;

  @override
  void dispose() {
    if (widget.lookup == null) _lookup.close();
    super.dispose();
  }

  void _setBusy(bool value) {
    setState(() => _busy = value);
    widget.onBusy(value);
  }

  Future<void> _scan() async {
    final code = await widget.scan(context);
    if (code == null || !mounted) return;
    setState(() {
      _note = null;
      _error = null;
    });
    _setBusy(true);
    try {
      final product = await _lookup.find(code, sources: widget.sources);
      if (!mounted) return;
      setState(() {
        _found = product;
        if (product == null) {
          _note = 'Produit $code introuvable : saisissez-le à la main.';
        }
      });
      if (product != null) widget.onFound(product);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton.icon(
        onPressed: _busy || !widget.enabled ? null : _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scanner le code-barres'),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Semantics(
            liveRegion: true,
            child: Text(_error!, style: const TextStyle(color: AppColors.red)),
          ),
        ),
      if (_note != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _note!,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
      if (_found != null) ProductFound(_found!),
      const SizedBox(height: 8),
    ],
  );
}

// The product a database found: photo, brand, source.
class ProductFound extends StatelessWidget {
  final ProductInfo product;
  const ProductFound(this.product, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        if (product.imageUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              product.imageUrl!,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              semanticLabel: product.name,
              errorBuilder: (_, _, _) => const SizedBox(width: 48, height: 48),
            ),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            [
              if (product.brand != null) product.brand!,
              'Fiche ${product.source.label} · ${product.barcode}',
            ].join('\n'),
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
