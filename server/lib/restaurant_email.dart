import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

const restaurantConfirmationPath = 'v1/restaurant/confirmation';

Handler restaurantEmail(Map<String, String> env) {
  final token = env['RESTAURANT_EMAIL_TOKEN']?.trim() ?? '';
  final apiKey = env['BREVO_API_KEY']?.trim() ?? '';
  final sender = env['BREVO_SENDER_EMAIL']?.trim() ?? '';
  final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  final uuid = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
  );
  Response json(int status, Map<String, Object?> body) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );

  return (request) async {
    if (request.method != 'POST') return Response(405);
    if (token.length < 32 || apiKey.isEmpty || !emailPattern.hasMatch(sender)) {
      return json(503, {'error': 'Service de confirmation non configuré.'});
    }
    if (request.headers['authorization'] != 'Bearer $token') {
      return Response(401);
    }
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      if (bytes.length + chunk.length > 4096) return Response(413);
      bytes.addAll(chunk);
    }
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return Response(400);
    }
    final email = data['email'];
    final key = data['idempotencyKey'];
    final reference = data['reference'];
    final guest = data['guest'];
    final table = data['table'];
    final seats = data['seats'];
    final starts = DateTime.tryParse(
      data['startsAt']?.toString() ?? '',
    )?.toUtc();
    if (email is! String ||
        email.length > 254 ||
        !emailPattern.hasMatch(email) ||
        key is! String ||
        !uuid.hasMatch(key) ||
        reference is! String ||
        !RegExp(r'^REST-\d{1,12}$').hasMatch(reference) ||
        guest is! String ||
        guest.trim().isEmpty ||
        guest.length > 120 ||
        (table != null && (table is! String || table.length > 40)) ||
        seats is! int ||
        seats < 1 ||
        seats > 20 ||
        starts == null) {
      return Response(400);
    }
    final time = starts
        .toIso8601String()
        .substring(0, 16)
        .replaceFirst('T', ' ');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final outgoing = await client.postUrl(
        Uri.https('api.brevo.com', '/v3/smtp/email'),
      );
      outgoing.headers.contentType = ContentType.json;
      outgoing.headers.set('api-key', apiKey);
      outgoing.write(
        jsonEncode({
          'sender': {'name': 'Nova Paris', 'email': sender},
          'to': [
            {'email': email},
          ],
          'headers': {'idempotencyKey': key},
          'subject': 'Nova Paris · Confirmation restaurant $reference',
          'textContent':
              'Bonjour $guest,\n\nVotre réservation au restaurant est confirmée.\n'
              'Référence : $reference\nDébut : $time UTC\n'
              'Personnes : $seats\nTable : ${table ?? 'attribuée à l’arrivée'}\n\nNova Paris',
        }),
      );
      final response = await outgoing.close().timeout(
        const Duration(seconds: 12),
      );
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 4));
      final result = jsonDecode(body);
      if (result is Map) {
        final messageId = result['messageId'];
        if (response.statusCode == 201 && messageId is String) {
          return json(200, {'accepted': true, 'messageId': messageId});
        }
        if (result['code'] == 'duplicate_parameter' &&
            result['message'].toString().toLowerCase().contains(
              'idempotency',
            )) {
          return json(200, {'accepted': true});
        }
      }
      return json(502, {'error': 'Confirmation non acceptée.'});
    } catch (_) {
      return json(502, {'error': 'Service e-mail indisponible.'});
    } finally {
      client.close(force: true);
    }
  };
}
