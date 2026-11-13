import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class RestaurantConfirmation {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static bool validEmail(String value) =>
      value.length <= 254 && _email.hasMatch(value);

  Future<void> send(Map<String, Object?> booking) async {
    const base = String.fromEnvironment('RESTAURANT_EMAIL_URL');
    const token = String.fromEnvironment('RESTAURANT_EMAIL_TOKEN');
    final url = Uri.tryParse(base);
    if (url == null ||
        !url.hasAuthority ||
        token.isEmpty ||
        (url.scheme != 'https' && !(kDebugMode && url.scheme == 'http'))) {
      throw StateError('Serveur de confirmation non configuré.');
    }
    final response = await http
        .post(
          url.resolve('/v1/restaurant/confirmation'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: jsonEncode(booking),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('Confirmation e-mail indisponible.');
    }
    final data = jsonDecode(response.body);
    if (data is! Map || data['accepted'] != true) {
      throw StateError('Confirmation e-mail non acceptée.');
    }
  }
}
