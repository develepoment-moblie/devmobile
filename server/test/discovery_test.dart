import 'dart:convert';
import 'dart:io';

import 'package:nova_sync_server/discovery.dart';
import 'package:nova_sync_server/sync_log.dart';
import 'package:test/test.dart';

void main() {
  test('the server id is made once and kept with the log file', () async {
    final directory = await Directory.systemTemp.createTemp('nova_srv_');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/log.db';
    final first = SyncLog.file(path);
    final id = first.serverId;
    first.close();
    final again = SyncLog.file(path);
    expect(again.serverId, id);
    again.close();
    final other = SyncLog.memory();
    expect(other.serverId, isNot(id));
    other.close();
  });

  test('the announcement reaches a phone listening on the network', () async {
    final phone = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(phone.close);
    final announcer = await Announcer.start(
      id: '3f2b8c1e-9a4d-4c7e-b1f0-6d2e8a9c0b13',
      name: 'PC-ACCUEIL',
      port: 8080,
      targets: () async => [InternetAddress.loopbackIPv4],
      toPort: phone.port,
      every: const Duration(milliseconds: 50),
    );
    addTearDown(announcer.stop);
    final received = await phone
        .where((e) => e == RawSocketEvent.read)
        .map((_) => phone.receive())
        .where((d) => d != null)
        .first
        .timeout(const Duration(seconds: 5));
    expect(jsonDecode(utf8.decode(received!.data)), {
      'service': 'nova-sync',
      'v': 1,
      'id': '3f2b8c1e-9a4d-4c7e-b1f0-6d2e8a9c0b13',
      'name': 'PC-ACCUEIL',
      'port': 8080,
    });
  });

  test('broadcast targets: the general address and each card\'s', () async {
    final targets = [for (final t in await broadcastTargets()) t.address];
    expect(targets, contains('255.255.255.255'));
    expect(targets.where((t) => t.startsWith('127.')), isEmpty);
    expect(targets.every((t) => t.endsWith('.255')), isTrue);
  });
}
