import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class StayingApiService {
  static const String baseUrl = 'https://api.stayingapi.com';

  static final Future<String> _configuredKey = _loadKey();
  static const _channel = MethodChannel('nova_paris/staying');

  static Future<String> _loadKey() async {
    const key = String.fromEnvironment('STAYING_API_KEY');
    if (key.trim().isNotEmpty) return key.trim();
    if (!kDebugMode ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return '';
    }
    try {
      return (await _channel.invokeMethod<String>('debugKey'))?.trim() ?? '';
    } on MissingPluginException {
      return '';
    }
  }

  static Future<bool> isConfigured() async => (await _configuredKey).isNotEmpty;

  Future<String> _requireKey() async {
    final key = await _configuredKey;
    if (key.isEmpty) {
      throw StateError('StayingAPI n’est pas configurée pour cette version.');
    }
    return key;
  }

  Future<List<dynamic>> searchHotels({
    required String location,
    required String checkIn,
    required String checkOut,
    required int adults,
  }) async {
    final key = await _requireKey();
    final uri = Uri.parse(
      '$baseUrl/v1/search'
      '?location=${Uri.encodeComponent(location)}'
      '&checkIn=$checkIn'
      '&checkOut=$checkOut'
      '&adults=$adults'
      '&platforms=google,booking'
      '&limit=20',
    );

    final response = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $key',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw StateError(
        'StayingAPI search failed (HTTP ${response.statusCode}).',
      );
    }

    final json = jsonDecode(response.body);

    return json['data'] ?? [];
  }

  // ==========================================================
  // GET HOTEL DETAILS + IMAGES
  // ==========================================================

  Future<Map<String, dynamic>> getHotelDetails({
    required String platform,
    required String id,
    String? country,
    String? checkIn,
    String? checkOut,
    int adults = 2,
  }) async {
    final key = await _requireKey();
    final queryParameters = <String, String>{'adults': adults.toString()};

    if (country != null && country.isNotEmpty && platform == 'booking') {
      queryParameters['country'] = country;
    }

    if (checkIn != null && checkIn.isNotEmpty) {
      queryParameters['checkIn'] = checkIn;
    }

    if (checkOut != null && checkOut.isNotEmpty) {
      queryParameters['checkOut'] = checkOut;
    }

    final uri = Uri.https(
      'api.stayingapi.com',
      '/v1/listing/$platform/$id',
      queryParameters,
    );

    final response = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $key',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw StateError(
        'StayingAPI listing failed (HTTP ${response.statusCode}).',
      );
    }

    final json = jsonDecode(response.body);

    return Map<String, dynamic>.from(json['data'] ?? {});
  }
}
