import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nova_sync_server/sync_api.dart';
import 'package:nova_sync_server/sync_log.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

// Waiting pulls (changes reach the other phones at once) and the copy of
// the data a joining phone starts from.
const a = '3f2b8c1e-9a4d-4c7e-b1f0-6d2e8a9c0b13';
const b = '7a1d2c3e-4b5f-4a6b-8c7d-9e0f1a2b3c4d';

Map<String, Object?> action(String id) => {
  'mutationId': id,
  'path': '/v1/rooms/204/start',
  'body': {'mutationId': id, 'version': 1},
  'actorId': 'sarah',
  'appliedAt': '2026-11-11T09:00:00.000',
};

void main() {
  late SyncLog log;
  late Handler api;
  setUp(() {
    log = SyncLog.memory();
    api = syncApi(log);
  });
  tearDown(() => log.close());

  Future<Response> get(String path) =>
      Future.value(api(Request('GET', Uri.parse('http://localhost$path'))));

  Future<Map<String, dynamic>> json(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, dynamic>;

  Future<void> push(String id) async {
    final r = await api(
      Request(
        'POST',
        Uri.parse('http://localhost/v1/sync/push'),
        body: jsonEncode({
          'deviceId': 'phone-1',
          'mutations': [action(id)],
        }),
      ),
    );
    expect(r.statusCode, 200);
  }

  Future<Response> putSnapshot(List<int> bytes, {int seq = 1}) async => api(
    Request(
      'PUT',
      Uri.parse('http://localhost/v1/sync/snapshot?seq=$seq&device=phone-1'),
      body: bytes,
    ),
  );

  group('a waiting pull', () {
    test('answers as soon as another phone pushes', () async {
      final watch = Stopwatch()..start();
      final waiting = get('/v1/sync/pull?since=0&wait=20');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await push(a);
      final page = await json(await waiting);
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect([for (final m in page['mutations']) m['mutationId']], [a]);
      expect(page['until'], 1);
    });

    test('answers at once when there is already something new', () async {
      await push(a);
      final watch = Stopwatch()..start();
      final page = await json(await get('/v1/sync/pull?since=0&wait=20'));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(page['mutations'], hasLength(1));
    });

    test('a push of an action already stored wakes nobody', () async {
      await push(a);
      final waiting = get('/v1/sync/pull?since=1&wait=1');
      await push(a);
      final page = await json(await waiting);
      expect(page['mutations'], isEmpty);
      expect(page['until'], 1);
    });

    test('nothing new: an empty page after the wait', () async {
      final watch = Stopwatch()..start();
      final page = await json(await get('/v1/sync/pull?since=0&wait=1'));
      expect(watch.elapsed, greaterThan(const Duration(milliseconds: 900)));
      expect(page['mutations'], isEmpty);
    });

    test('wait is limited to 30 seconds', () async {
      expect((await get('/v1/sync/pull?since=0&wait=31')).statusCode, 400);
      expect((await get('/v1/sync/pull?since=0&wait=-1')).statusCode, 400);
    });
  });

  group('the copy of the data', () {
    final gz = gzip.encode(utf8.encode('{"rooms":[]}'));

    test('none at first', () async {
      expect((await get('/v1/sync/snapshot')).statusCode, 404);
      expect((await json(await get('/v1/health')))['snapshotSeq'], isNull);
    });

    test('kept, given back with its number, only when newer', () async {
      await push(a);
      await push(b);
      var r = await putSnapshot(gz, seq: 1);
      expect(await json(r), {'stored': true, 'snapshotSeq': 1});

      r = await get('/v1/sync/snapshot');
      expect(r.statusCode, 200);
      expect(r.headers['x-snapshot-seq'], '1');
      expect(r.headers['content-type'], 'application/gzip');
      expect(
        utf8.decode(gzip.decode(await r.read().expand((c) => c).toList())),
        '{"rooms":[]}',
      );

      expect(await json(await putSnapshot(gz, seq: 1)), {
        'stored': false,
        'snapshotSeq': 1,
      });
      expect((await json(await putSnapshot(gz, seq: 2)))['stored'], isTrue);
      expect((await json(await get('/v1/health')))['snapshotSeq'], 2);
    });

    test('not for a number the server never gave', () async {
      await push(a);
      expect((await json(await putSnapshot(gz, seq: 5)))['stored'], isFalse);
      expect((await json(await putSnapshot(gz, seq: 0)))['stored'], isFalse);
    });

    test('gzip only, seq and device required', () async {
      await push(a);
      expect((await putSnapshot(utf8.encode('{"x":1}'))).statusCode, 400);
      final r = await api(
        Request(
          'PUT',
          Uri.parse('http://localhost/v1/sync/snapshot'),
          body: gz,
        ),
      );
      expect(r.statusCode, 400);
      expect(
        (await api(
          Request('DELETE', Uri.parse('http://localhost/v1/sync/snapshot')),
        )).statusCode,
        405,
      );
    });

    test('kept in the log file', () async {
      final directory = await Directory.systemTemp.createTemp('nova_snap_');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/log.db';
      var file = SyncLog.file(path);
      syncApi(file);
      file.push('phone-1', [action(a)]);
      expect(file.saveSnapshot(1, 'phone-1', Uint8List.fromList(gz)), isTrue);
      file.close();
      file = SyncLog.file(path);
      expect(file.snapshot()?.seq, 1);
      file.close();
    });
  });
}
