import 'dart:async';
import 'dart:convert';
import 'dart:io';

// The server announces itself on the hotel's Wi-Fi, so a phone finds it
// without typing its address (lib/housekeeping/services/server_discovery.dart
// in the app). Every [Announcer.every], a short UDP message goes to the
// network's broadcast address on [discoveryPort]:
//
//   {"service":"nova-sync","v":1,"id":"<server id>","name":"PC-ACCUEIL","port":8080}
//
// The phone takes the address the message came from (never one written in
// it) and checks the id with GET /v1/health before trusting it.

/// UDP port the phones listen on.
const discoveryPort = 45454;

/// The message sent on the Wi-Fi.
List<int> announcement({
  required String id,
  required String name,
  required int port,
}) => utf8.encode(
  jsonEncode({
    'service': 'nova-sync',
    'v': 1,
    'id': id,
    'name': name,
    'port': port,
  }),
);

/// Where to send: the general broadcast address, and the broadcast address
/// of each network card (x.y.z.255), because Windows sends the general one
/// out of a single card only. A /24 network is assumed: the usual hotel or
/// home Wi-Fi.
Future<List<InternetAddress>> broadcastTargets() async {
  final targets = {'255.255.255.255'};
  for (final interface in await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  )) {
    for (final address in interface.addresses) {
      if (address.isLoopback || address.isLinkLocal) continue;
      final parts = address.address.split('.');
      targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
    }
  }
  return [for (final t in targets) InternetAddress(t)];
}

class Announcer {
  final RawDatagramSocket _socket;
  final List<int> _message;
  final int _toPort;
  final Future<List<InternetAddress>> Function() _targets;
  Timer? _timer;

  Announcer._(this._socket, this._message, this._toPort, this._targets);

  /// Starts announcing now, then every [every]. [targets] and [toPort]:
  /// tests send to 127.0.0.1 on a free port.
  static Future<Announcer> start({
    required String id,
    required String name,
    required int port,
    Duration every = const Duration(seconds: 2),
    Future<List<InternetAddress>> Function()? targets,
    int toPort = discoveryPort,
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
      ..broadcastEnabled = true;
    final announcer = Announcer._(
      socket,
      announcement(id: id, name: name, port: port),
      toPort,
      targets ?? broadcastTargets,
    );
    await announcer._send();
    announcer._timer = Timer.periodic(every, (_) => announcer._send());
    return announcer;
  }

  // The cards are listed again each time: the Wi-Fi may come back with
  // another address while the server runs.
  Future<void> _send() async {
    for (final target in await _targets()) {
      try {
        _socket.send(_message, target, _toPort);
      } on SocketException {
        // A card without a network (cable unplugged): the others still get it.
      }
    }
  }

  void stop() {
    _timer?.cancel();
    _socket.close();
  }
}
