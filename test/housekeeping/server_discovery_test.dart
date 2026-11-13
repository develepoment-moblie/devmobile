import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/services/server_discovery.dart';

// Reading the server's announcements on the Wi-Fi (server/lib/discovery.dart).
void main() {
  const id = '3f2b8c1e-9a4d-4c7e-b1f0-6d2e8a9c0b13';
  final lan = InternetAddress('192.168.1.11');
  List<int> message(Map<String, Object?> json) => utf8.encode(jsonEncode(json));
  Map<String, Object?> valid({Object? port = 8080, Object? name = 'PC'}) => {
    'service': 'nova-sync',
    'v': 1,
    'id': id,
    'name': name,
    'port': port,
  };

  group('an announcement', () {
    test('gives the address it came from and the announced port', () {
      final server = readAnnouncement(message(valid(port: 9000)), lan)!;
      expect(server.id, id);
      expect(server.name, 'PC');
      expect(server.address, Uri.parse('http://192.168.1.11:9000'));
      expect(server.hostPort, '192.168.1.11:9000');
    });

    test('never an address written in the message', () {
      final server = readAnnouncement(
        message({...valid(), 'host': '8.8.8.8', 'address': '8.8.8.8'}),
        lan,
      )!;
      expect(server.address.host, '192.168.1.11');
    });

    test('only from the local network', () {
      expect(
        readAnnouncement(message(valid()), InternetAddress('8.8.8.8')),
        isNull,
      );
      expect(
        readAnnouncement(message(valid()), InternetAddress('::1')),
        isNull,
      );
      expect(
        readAnnouncement(message(valid()), InternetAddress('10.0.0.5')),
        isNotNull,
      );
    });

    test('anything else is ignored', () {
      for (final bad in <List<int>>[
        utf8.encode('hello'),
        utf8.encode('[1, 2]'),
        [0xff, 0xfe, 0x00],
        message({...valid(), 'service': 'other'}),
        message({...valid(), 'v': 2}),
        message({...valid(), 'id': ''}),
        message({...valid(), 'id': 'x' * 65}),
        message({...valid(), 'id': 42}),
        message(valid(port: 0)),
        message(valid(port: 70000)),
        message(valid(port: '8080')),
        List.filled(2000, 32),
      ]) {
        expect(
          readAnnouncement(bad, lan),
          isNull,
          reason: utf8.decode(bad, allowMalformed: true),
        );
      }
    });

    test('a missing or long name gets a short label', () {
      expect(
        readAnnouncement(message(valid(name: null)), lan)!.name,
        'Serveur Nova Paris',
      );
      expect(
        readAnnouncement(message(valid(name: '  ')), lan)!.name,
        'Serveur Nova Paris',
      );
      expect(
        readAnnouncement(message(valid(name: 'N' * 80)), lan)!.name,
        hasLength(40),
      );
    });
  });

  group('listening', () {
    // A free port for each test, so the real port 45454 is never needed.
    Future<int> freePort() async {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = socket.port;
      socket.close();
      return port;
    }

    test('a real announcement on this computer is heard', () async {
      final port = await freePort();
      final discovery = ServerDiscovery(port: port);
      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(sender.close);
      final heard = discovery.find(id, const Duration(seconds: 5));
      // Sent a few times: the socket opens asynchronously.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        sender.send(message(valid()), InternetAddress.loopbackIPv4, port);
      }
      final server = await heard;
      expect(server?.address, Uri.parse('http://127.0.0.1:8080'));
    });

    test('nothing heard: find gives up after the delay', () async {
      final discovery = ServerDiscovery(port: await freePort());
      final watch = Stopwatch()..start();
      expect(
        await discovery.find(id, const Duration(milliseconds: 200)),
        isNull,
      );
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });

    test('the socket closes when nobody listens, and opens again', () async {
      final port = await freePort();
      final discovery = ServerDiscovery(port: port);
      final first = discovery.watch().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await first.cancel();
      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(sender.close);
      final heard = discovery.find(id, const Duration(seconds: 5));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        sender.send(message(valid()), InternetAddress.loopbackIPv4, port);
      }
      expect(await heard, isNotNull);
    });
  });
}
