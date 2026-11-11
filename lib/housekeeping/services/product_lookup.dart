import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_exception.dart';

// Finds a packaged product by its barcode in Open Food Facts (free, no key),
// to fill in a minibar item: scan the can, the name comes by itself.
//   GET https://world.openfoodfacts.org/api/v2/product/<barcode>.json
// Only the barcode leaves the phone.

/// What Open Food Facts knows about a product.
class ProductInfo {
  final String barcode, name;
  final String? brand, quantity, imageUrl;
  const ProductInfo({
    required this.barcode,
    required this.name,
    this.brand,
    this.quantity,
    this.imageUrl,
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

  /// The product, or null when Open Food Facts does not know it.
  Future<ProductInfo?> find(String barcode) async {
    if (!isProductBarcode(barcode)) {
      throw const AppServiceException('Code-barres invalide.');
    }
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.https(
              'world.openfoodfacts.org',
              '/api/v2/product/$barcode.json',
              {
                'fields': 'product_name,product_name_fr,brands,quantity,image_front_small_url',
              },
            ),
            // Open Food Facts asks apps to name themselves.
            headers: {'user-agent': 'NovaParis/1.0 (projet etudiant)'},
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AppServiceException(
        'Open Food Facts ne répond pas. Saisissez l’article à la main.',
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
        'Open Food Facts indisponible (${response.statusCode}).',
      );
    }
    final Map<String, dynamic> json;
    try {
      json = (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
          .cast<String, dynamic>();
    } on FormatException {
      throw const AppServiceException('Réponse illisible d’Open Food Facts.');
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
    );
  }

  void close() => _client.close();
}
