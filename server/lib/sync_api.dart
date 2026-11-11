import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'sync_log.dart';

// The REST API of the hotel sync server.
//
//   GET  /v1/health                         is the server up, how many actions
//   POST /v1/sync/push                      a phone sends its queued actions
//   GET  /v1/sync/pull?since=&device=&limit= the other phones' actions
//   GET  /v1/rooms/activity                 last action per room (browser)
//
// Requests and answers are JSON. A repeated mutationId is answered
// "duplicate" and stored once, so a phone can always retry.

/// Largest request accepted (a batch with photos).
const maxBodyBytes = 25 * 1024 * 1024;

Response _json(Object body, [int status = 200]) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Response _error(int status, String message) =>
    _json({'error': message}, status);

Handler syncApi(SyncLog log) => (Request request) async {
  final path = '/${request.url.path}';
  final method = request.method;
  try {
    if (method == 'GET' && path == '/v1/health') {
      return _json({
        'status': 'ok',
        'mutations': log.count,
        'lastSeq': log.lastSeq,
      });
    }
    if (method == 'GET' && path == '/v1/rooms/activity') {
      return _json({'rooms': log.roomActivity()});
    }
    if (method == 'GET' && path == '/v1/sync/pull') {
      final q = request.url.queryParameters;
      final since = int.tryParse(q['since'] ?? '0');
      final device = q['device'];
      final limit = int.tryParse(q['limit'] ?? '50');
      if (since == null || since < 0) return _error(400, 'since invalide.');
      if (device == null || device.isEmpty) {
        return _error(400, 'device requis.');
      }
      if (limit == null || limit < 1 || limit > 200) {
        return _error(400, 'limit de 1 à 200.');
      }
      final page = log.pull(since, device, limit);
      return _json({
        'mutations': page.mutations,
        'until': page.until,
        'more': page.more,
      });
    }
    if (method == 'POST' && path == '/v1/sync/push') {
      final length = request.contentLength;
      if (length != null && length > maxBodyBytes) {
        return _error(413, 'Envoi trop volumineux.');
      }
      final Object? body;
      try {
        body = jsonDecode(await request.readAsString());
      } on FormatException {
        return _error(400, 'JSON invalide.');
      }
      if (body is! Map ||
          body['deviceId'] is! String ||
          (body['deviceId'] as String).isEmpty ||
          body['mutations'] is! List) {
        return _error(400, 'deviceId et mutations requis.');
      }
      final mutations = body['mutations'] as List;
      if (mutations.length > 200) {
        return _error(413, '200 actions maximum par envoi.');
      }
      return _json({
        'results': log.push(body['deviceId'] as String, mutations),
        'lastSeq': log.lastSeq,
      });
    }
    if (const {
      '/v1/health',
      '/v1/rooms/activity',
      '/v1/sync/pull',
      '/v1/sync/push',
    }.contains(path)) {
      return _error(405, 'Méthode non autorisée.');
    }
    return _error(404, 'Ressource inconnue.');
  } catch (e) {
    return _error(500, 'Erreur du serveur.');
  }
};
