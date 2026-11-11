import 'dart:io';

import 'package:args/args.dart';
import 'package:nova_sync_server/sync_api.dart';
import 'package:nova_sync_server/sync_log.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

// Starts the hotel sync server: dart run bin/server.dart [--port 8080]
// [--db data/nova_sync.db]. The phones on the same Wi-Fi reach it at
// http://<this computer's address>:<port>.
Future<void> main(List<String> args) async {
  final options =
      (ArgParser()
            ..addOption('port', defaultsTo: '8080')
            ..addOption('db', defaultsTo: 'data/nova_sync.db'))
          .parse(args);
  final port = int.parse(options['port'] as String);
  final dbPath = options['db'] as String;
  await File(dbPath).parent.create(recursive: true);
  final log = SyncLog.file(dbPath);

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(syncApi(log));
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);

  stdout.writeln('Serveur de synchronisation Nova Paris');
  stdout.writeln(
    'Journal : ${File(dbPath).absolute.path} (${log.count} actions)',
  );
  stdout.writeln('Adresses à saisir dans l’application :');
  for (final interface in await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  )) {
    for (final address in interface.addresses) {
      stdout.writeln(
        '  ${address.address}:${server.port}  (${interface.name})',
      );
    }
  }
  stdout.writeln('Ctrl+C pour arrêter.');

  ProcessSignal.sigint.watch().listen((_) async {
    await server.close();
    log.close();
    exit(0);
  });
}
