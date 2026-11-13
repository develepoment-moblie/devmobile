import 'dart:io';

import 'package:args/args.dart';
import 'package:nova_sync_server/discovery.dart';
import 'package:nova_sync_server/sync_api.dart';
import 'package:nova_sync_server/sync_log.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

// Starts the hotel sync server: dart run bin/server.dart [--port 8080]
// [--db data/nova_sync.db] [--no-discovery]. The phones on the same Wi-Fi reach it at
// http://<this computer's address>:<port>, and find it by themselves on the
// Wi-Fi unless --no-discovery is given (lib/discovery.dart).
Future<void> main(List<String> args) async {
  final options =
      (ArgParser()
            ..addOption('port', defaultsTo: '8080')
            ..addOption('db', defaultsTo: 'data/nova_sync.db')
            ..addFlag('discovery', defaultsTo: true))
          .parse(args);
  final port = int.parse(options['port'] as String);
  final dbPath = options['db'] as String;
  await File(dbPath).parent.create(recursive: true);
  final log = SyncLog.file(dbPath);
  final name = Platform.localHostname;

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(syncApi(log, name: name));
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  final announcer = options['discovery'] as bool
      ? await Announcer.start(id: log.serverId, name: name, port: server.port)
      : null;

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
  stdout.writeln(
    announcer == null
        ? 'Annonce sur le Wi-Fi : désactivée (--no-discovery).'
        : 'Annonce sur le Wi-Fi : activée (UDP $discoveryPort), les '
              'téléphones trouvent ce serveur tout seuls.',
  );
  stdout.writeln('Ctrl+C pour arrêter.');

  ProcessSignal.sigint.watch().listen((_) async {
    announcer?.stop();
    await server.close();
    log.close();
    exit(0);
  });
}
