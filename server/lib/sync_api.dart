import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import 'sync_log.dart';

// The REST API of the hotel sync server.
//
//   GET  /v1/health                         is the server up, its id and name,
//                                           how many actions
//   POST /v1/sync/push                      a phone sends its queued actions
//   GET  /v1/sync/pull?since=&limit=&wait= every action after since, in order;
//                                           with wait (seconds, up to 30) and
//                                           nothing new, answers as soon as a
//                                           phone pushes something
//   PUT  /v1/sync/snapshot?seq=&device=     a phone's confirmed data (gzip)
//   GET  /v1/sync/snapshot                  the latest one (x-snapshot-seq)
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

/// [name]: shown on the phones that find this server on the Wi-Fi.
Handler syncApi(SyncLog log, {String name = 'Serveur Nova Paris'}) =>
    (Request request) async {
      final path = '/${request.url.path}';
      final method = request.method;
      try {
        if (method == 'GET' && path == '/v1/health') {
          return _json({
            'status': 'ok',
            'serverId': log.serverId,
            'name': name,
            'mutations': log.count,
            'lastSeq': log.lastSeq,
            'snapshotSeq': log.snapshotSeq,
          });
        }
        if (method == 'GET' && path == '/v1/rooms/activity') {
          return _json({'rooms': log.roomActivity()});
        }
        if (method == 'GET' && path == '/v1/sync/pull') {
          final q = request.url.queryParameters;
          final since = int.tryParse(q['since'] ?? '0');
          // device= (the asking phone) is accepted but not needed: every phone
          // gets the whole list, its own actions included.
          final limit = int.tryParse(q['limit'] ?? '50');
          if (since == null || since < 0) return _error(400, 'since invalide.');
          if (limit == null || limit < 1 || limit > 200) {
            return _error(400, 'limit de 1 à 200.');
          }
          final wait = int.tryParse(q['wait'] ?? '0');
          if (wait == null || wait < 0 || wait > 30) {
            return _error(400, 'wait de 0 à 30.');
          }
          if (wait > 0) await log.waitForMore(since, Duration(seconds: wait));
          final page = log.pull(since, limit);
          return _json({
            'mutations': page.mutations,
            'until': page.until,
            'more': page.more,
          });
        }
        if (method == 'GET' && path == '/v1/sync/snapshot') {
          final snapshot = log.snapshot();
          if (snapshot == null) return _error(404, 'Aucune copie des données.');
          return Response.ok(
            snapshot.data,
            headers: {
              'content-type': 'application/gzip',
              'x-snapshot-seq': '${snapshot.seq}',
            },
          );
        }
        if (method == 'PUT' && path == '/v1/sync/snapshot') {
          final q = request.url.queryParameters;
          final seq = int.tryParse(q['seq'] ?? '');
          final device = q['device'] ?? '';
          if (seq == null || device.isEmpty) {
            return _error(400, 'seq et device requis.');
          }
          final length = request.contentLength;
          if (length != null && length > maxBodyBytes) {
            return _error(413, 'Envoi trop volumineux.');
          }
          final data = BytesBuilder(copy: false);
          await for (final chunk in request.read()) {
            data.add(chunk);
            if (data.length > maxBodyBytes) {
              return _error(413, 'Envoi trop volumineux.');
            }
          }
          final bytes = data.takeBytes();
          // gzip only: the phones read it back as such.
          if (bytes.length < 2 || bytes[0] != 0x1f || bytes[1] != 0x8b) {
            return _error(400, 'Copie invalide (gzip attendu).');
          }
          return _json({
            'stored': log.saveSnapshot(seq, device, bytes),
            'snapshotSeq': log.snapshotSeq,
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
          '/v1/sync/snapshot',
        }.contains(path)) {
          return _error(405, 'Méthode non autorisée.');
        }
        return _error(404, 'Ressource inconnue.');
      } catch (e) {
        return _error(500, 'Erreur du serveur.');
      }
    };
