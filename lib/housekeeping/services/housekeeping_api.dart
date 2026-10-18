import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'housekeeping_backend.dart';
import '../../shared/services/app_exception.dart';
export '../../shared/services/app_exception.dart' show HousekeepingException;

// Token supplied by the team's user module, including refresh when needed.
class HousekeepingApi implements HousekeepingBackend {
  final Uri baseUrl;
  final Future<String> Function() tokenProvider;
  final http.Client _client;
  HousekeepingApi({
    required this.baseUrl,
    required this.tokenProvider,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    if (!['http', 'https'].contains(baseUrl.scheme) ||
        baseUrl.host.isEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment ||
        baseUrl.userInfo.isNotEmpty) {
      throw ArgumentError('Adresse API invalide.');
    }
    if (const bool.fromEnvironment('dart.vm.product') &&
        baseUrl.scheme != 'https') {
      throw ArgumentError('HTTPS requis en version release.');
    }
  }
  @override
  Future<Map<String, dynamic>> snapshot() => _request('GET', '/v1/snapshot');
  @override
  Future<void> mutate(String path, Map<String, dynamic> body) async {
    final random = Random.secure();
    final key = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    // Reuse the key for a bounded retry if the first result was lost in transit.
    await _request('POST', path, body: body, key: key);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? key,
  }) async {
    final token = await tokenProvider();
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final headers = {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Idempotency-Key': ?key,
        };
        final uri = baseUrl.resolve(path);
        final response =
            await (method == 'GET'
                    ? _client.get(uri, headers: headers)
                    : _client.post(
                        uri,
                        headers: headers,
                        body: jsonEncode(body),
                      ))
                .timeout(const Duration(seconds: 12));
        final json =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        if (response.statusCode != 200) {
          throw HousekeepingException(
            json['error'] as String? ?? 'Serveur indisponible.',
            response.statusCode,
          );
        }
        return json;
      } on HousekeepingException {
        rethrow;
      } on FormatException {
        throw const HousekeepingException('Réponse serveur invalide.');
      } on Object catch (error) {
        if (error is! TimeoutException && error is! http.ClientException) {
          rethrow;
        }
        if (attempt == 1) {
          throw const HousekeepingException(
            'Connexion interrompue. Résultat non confirmé : actualisez avant de réessayer.',
          );
        }
      }
    }
    throw const HousekeepingException('Serveur inaccessible.');
  }

  @override
  void close() => _client.close();
}
