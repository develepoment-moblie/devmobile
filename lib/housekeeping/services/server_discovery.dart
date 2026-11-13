import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'housekeeping_sync.dart' show isLocalNetworkHost;

// Finds the hotel sync server on the Wi-Fi (server/lib/discovery.dart). The
// server sends a short UDP message every 2 seconds on [discoveryPort]:
//   {"service":"nova-sync","v":1,"id":"<server id>","name":"PC-ACCUEIL","port":8080}
// The address used is the one the message came from, never one written in
// it, and it must be on the local network. The id is checked with
// GET /v1/health before the phone trusts the server (HousekeepingSync).

/// UDP port the server announces itself on.
const discoveryPort = 45454;

/// A server heard on the Wi-Fi.
class FoundServer {
  final String id, name;
  final Uri address;
  const FoundServer({
    required this.id,
    required this.name,
    required this.address,
  });

  /// "192.168.1.11:8080", as typed in the address field.
  String get hostPort => '${address.host}:${address.port}';

  @override
  bool operator ==(Object other) =>
      other is FoundServer &&
      other.id == id &&
      other.name == name &&
      other.address == address;

  @override
  int get hashCode => Object.hash(id, name, address);
}

/// The server announced by [data], sent from [from]; null when it is not a
/// Nova Paris announcement or does not come from the local network.
FoundServer? readAnnouncement(List<int> data, InternetAddress from) {
  if (data.length > 1024) return null;
  if (from.type != InternetAddressType.IPv4 ||
      !isLocalNetworkHost(from.address)) {
    return null;
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(data));
  } on FormatException {
    return null;
  }
  if (json is! Map || json['service'] != 'nova-sync' || json['v'] != 1) {
    return null;
  }
  final id = json['id'], port = json['port'], name = json['name'];
  if (id is! String || id.isEmpty || id.length > 64) return null;
  if (port is! int || port < 1 || port > 65535) return null;
  final label = name is String ? name.trim() : '';
  return FoundServer(
    id: id,
    name: label.isEmpty
        ? 'Serveur Nova Paris'
        : label.substring(0, label.length.clamp(0, 40)),
    address: Uri(scheme: 'http', host: from.address, port: port),
  );
}

/// Listens for the servers' announcements. One socket for the whole app,
/// open while someone listens (the Synchronisation screen, or the sync
/// looking for its server's new address).
class ServerDiscovery {
  final int port;
  ServerDiscovery({this.port = discoveryPort});

  RawDatagramSocket? _socket;
  late final _found = StreamController<FoundServer>.broadcast(
    onListen: _open,
    onCancel: _close,
  );

  /// Every announcement heard, as long as the subscription lasts. When the
  /// Wi-Fi does not let the phone listen, nothing comes (typing the address
  /// still works).
  Stream<FoundServer> watch() => _found.stream;

  /// The first announcement of server [id] within [within], or null.
  Future<FoundServer?> find(String id, Duration within) => watch()
      .where((s) => s.id == id)
      .cast<FoundServer?>()
      .first
      .timeout(within, onTimeout: () => null);

  Future<void> _open() async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      // Nobody listens any more, or a second opening won the race.
      if (!_found.hasListener || _socket != null) {
        socket.close();
        return;
      }
      _socket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final server = readAnnouncement(datagram.data, datagram.address);
        if (server != null && _found.hasListener) _found.add(server);
      });
    } on SocketException {
      // Port taken or no network: no server will be found, typing works.
    }
  }

  void _close() {
    _socket?.close();
    _socket = null;
  }
}
