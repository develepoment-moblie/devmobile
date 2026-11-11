import 'dart:convert';

import 'package:nova_sync_server/sync_api.dart';
import 'package:nova_sync_server/sync_log.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const a = '3f2b8c1e-9a4d-4c7e-b1f0-6d2e8a9c0b13';
const b = '7a1d2c3e-4b5f-4a6b-8c7d-9e0f1a2b3c4d';
const c = '0b1c2d3e-4f5a-4b6c-9d7e-8f9a0b1c2d3e';

Map<String, Object?> action(String id, String path, {String actor = 'sarah'}) =>
    {
      'mutationId': id,
      'path': path,
      'body': {'mutationId': id, 'version': 1},
      'actorId': actor,
      'appliedAt': '2026-11-11T09:00:00.000',
    };

void main() {
  late SyncLog log;
  late Handler api;
  setUp(() {
    log = SyncLog.memory(clock: () => DateTime(2026, 11, 11, 9));
    api = syncApi(log);
  });
  tearDown(() => log.close());

  Future<(int, Map<String, dynamic>)> call(
    String method,
    String path, [
    Object? body,
  ]) async {
    final response = await api(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return (
      response.statusCode,
      jsonDecode(await response.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> push(String device, List<Object?> list) async {
    final (status, json) = await call('POST', '/v1/sync/push', {
      'deviceId': device,
      'mutations': list,
    });
    expect(status, 200);
    return json;
  }

  test('health answers with the number of actions', () async {
    final (status, json) = await call('GET', '/v1/health');
    expect(status, 200);
    expect(json, {'status': 'ok', 'mutations': 0, 'lastSeq': 0});
  });

  test('push stores new actions once: a retry is a duplicate', () async {
    final first = await push('phone-1', [
      action(a, '/v1/rooms/204/submit'),
      action(b, '/v1/rooms/204/approve', actor: 'amina'),
    ]);
    expect(
      [for (final r in first['results']) r['status']],
      ['applied', 'applied'],
    );
    final again = await push('phone-1', [action(a, '/v1/rooms/204/submit')]);
    expect(again['results'].single['status'], 'duplicate');
    expect(log.count, 2);
  });

  test('a malformed action is rejected, the others are kept', () async {
    final result = await push('phone-1', [
      action('not-a-uuid', '/v1/rooms/204/submit'),
      action(a, '/etc/passwd'),
      {
        ...action(b, '/v1/rooms/204/submit'),
        'body': {'mutationId': c},
      },
      action(c, 'catalog/create', actor: 'manager'),
    ]);
    expect(
      [for (final r in result['results']) r['status']],
      ['rejected', 'rejected', 'rejected', 'applied'],
    );
    expect(log.count, 1);
  });

  test(
    "pull gives every action in the server's order, own ones included",
    () async {
      await push('phone-1', [action(a, '/v1/rooms/204/submit')]);
      await push('phone-2', [
        action(b, '/v1/rooms/204/approve', actor: 'amina'),
      ]);
      await push('phone-1', [action(c, '/v1/rooms/305/start')]);

      // The phones rebuild their data in this order, their own actions too.
      final (_, all) = await call(
        'GET',
        '/v1/sync/pull?since=0&device=phone-2&limit=50',
      );
      expect([for (final m in all['mutations']) m['mutationId']], [a, b, c]);
      expect([for (final m in all['mutations']) m['seq']], [1, 2, 3]);
      expect(all['mutations'].first['body'], {'mutationId': a, 'version': 1});
      expect(all['until'], 3);
      expect(all['more'], false);

      // Pages; device= is optional.
      final (_, page) = await call('GET', '/v1/sync/pull?since=0&limit=2');
      expect([for (final m in page['mutations']) m['mutationId']], [a, b]);
      expect(page['until'], 2);
      expect(page['more'], true);
      final (_, next) = await call('GET', '/v1/sync/pull?since=2&limit=2');
      expect(next['mutations'].single['mutationId'], c);
      expect(next['more'], false);
    },
  );

  test('room activity shows the last action of each room', () async {
    await push('phone-1', [
      action(a, '/v1/rooms/204/submit'),
      action(b, '/v1/rooms/204/approve', actor: 'amina'),
      action(c, '/v1/supplies/new/create', actor: 'amina'),
    ]);
    final (status, json) = await call('GET', '/v1/rooms/activity');
    expect(status, 200);
    expect(json['rooms'], [
      {
        'room': '204',
        'lastAction': 'approve',
        'by': 'amina',
        'at': '2026-11-11T09:00:00.000',
        'seq': 2,
        'actions': 2,
      },
    ]);
  });

  test('bad requests get a clear status', () async {
    expect((await call('GET', '/v1/sync/pull?since=-1')).$1, 400);
    expect((await call('GET', '/v1/sync/pull?since=0&limit=500')).$1, 400);
    expect((await call('POST', '/v1/sync/push', {'deviceId': 'x'})).$1, 400);
    expect((await call('GET', '/v1/sync/push')).$1, 405);
    expect((await call('GET', '/v1/nothing')).$1, 404);
  });
}
