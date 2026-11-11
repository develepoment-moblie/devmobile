import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_exception.dart';

// Finds a packaged product by its barcode, to fill in a stock item: scan it,
// the name comes by itself. Two free databases, no key, same API:
//  - Open Food Facts: drinks and snacks (the minibar);
//  - Open Beauty Facts: shower gel, shampoo, soap (the guest amenities).
//   GET https://world.open{food|beauty}facts.org/api/v2/product/<code>.json
// Only the barcode leaves the phone.

/// Where a product sheet comes from.
enum ProductSource {
  food('Open Food Facts', 'world.openfoodfacts.org'),
  beauty('Open Beauty Facts', 'world.openbeautyfacts.org');

  final String label, host;
  const ProductSource(this.label, this.host);
}

/// What Open Food Facts knows about a product.
class ProductInfo {
  final String barcode, name;
  final String? brand, quantity, imageUrl;
  final ProductSource source;
  const ProductInfo({
    required this.barcode,
    required this.name,
    this.brand,
    this.quantity,
    this.imageUrl,
    this.source = ProductSource.food,
  });

  /// "Coca-Cola 330 ml": the name and the size, 80 characters at most (the
  /// minibar item's limit).
  String get label {
    final size = quantity?.trim() ?? '';
    final text = size.isEmpty || name.toLowerCase().contains(size.toLowerCase())
        ? name
        : '$name $size';
    return text.length <= 80 ? text : text.substring(0, 80).trimRight();
  }
}

/// EAN-8, UPC (12) and EAN-13 / EAN-14 codes: 8 to 14 digits.
bool isProductBarcode(String? code) =>
    code != null && RegExp(r'^\d{8,14}$').hasMatch(code);

class ProductLookup {
  final http.Client _client;
  final Duration timeout;
  ProductLookup({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  /// The product from the first of [sources] that knows it, or null.
  Future<ProductInfo?> find(
    String barcode, {
    List<ProductSource> sources = const [ProductSource.food],
  }) async {
    if (!isProductBarcode(barcode)) {
      throw const AppServiceException('Code-barres invalide.');
    }
    for (final source in sources) {
      final product = await _find(barcode, source);
      if (product != null) return product;
    }
    return null;
  }

  Future<ProductInfo?> _find(String barcode, ProductSource source) async {
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.https(source.host, '/api/v2/product/$barcode.json', {
              'fields': 'product_name,product_name_fr,brands,quantity,image_front_small_url',
            }),
            // These databases ask apps to name themselves.
            headers: {'user-agent': 'NovaParis/1.0 (projet etudiant)'},
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AppServiceException(
        '${source.label} ne répond pas. Saisissez l’article à la main.',
      );
    } on SocketException {
      throw const AppServiceException(
        'Pas de connexion Internet. Saisissez l’article à la main.',
      );
    } on http.ClientException {
      throw const AppServiceException(
        'Pas de connexion Internet. Saisissez l’article à la main.',
      );
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw AppServiceException(
        '${source.label} indisponible (${response.statusCode}).',
      );
    }
    final Map<String, dynamic> json;
    try {
      json = (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
          .cast<String, dynamic>();
    } on FormatException {
      throw AppServiceException('Réponse illisible de ${source.label}.');
    }
    final product = json['product'];
    if (json['status'] != 1 || product is! Map) return null;
    String? field(String key) {
      final value = product[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final name = field('product_name_fr') ?? field('product_name');
    if (name == null) return null;
    return ProductInfo(
      barcode: barcode,
      name: name,
      brand: field('brands'),
      quantity: field('quantity'),
      imageUrl: field('image_front_small_url'),
      source: source,
    );
  }

  void close() => _client.close();
}
