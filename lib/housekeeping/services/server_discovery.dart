import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'housekeeping_sync.dart' show isLocalNetworkHost;

// Finds the hotel sync server on the Wi-Fi, two ways at once:
//
//  1. Announcements (server/lib/discovery.dart): the server sends a short
//     UDP message every 2 seconds on [discoveryPort]:
//       {"service":"nova-sync","v":1,"id":"<server id>","name":"PC-ACCUEIL","port":8080}
//     The address used is the one the message came from, never one written
//     in it, and it must be on the local network.
//  2. A scan ([ServerDiscovery.scan]): many phones and routers drop
//     broadcast messages (seen on a Xiaomi, Android 14). The phone then
//     tries the server's port on every address of its own network (x.y.z.1
//     to .254); HousekeepingSync asks GET /v1/health on the ones that answer.
//
// Either way, the id is checked with GET /v1/health before the phone trusts
// the server (HousekeepingSync).

/// UDP port the server announces itself on.
const discoveryPort = 45454;

/// The port the server listens on unless started with --port.
const defaultServerPort = 8080;

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

/// A server's name as shown on the phone: trimmed, 40 characters at most.
String serverLabel(Object? name) {
  final label = name is String ? name.trim() : '';
  return label.isEmpty
      ? 'Serveur Nova Paris'
      : label.substring(0, label.length.clamp(0, 40));
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
  final id = json['id'], port = json['port'];
  if (id is! String || id.isEmpty || id.length > 64) return null;
  if (port is! int || port < 1 || port > 65535) return null;
  return FoundServer(
    id: id,
    name: serverLabel(json['name']),
    address: Uri(scheme: 'http', host: from.address, port: port),
  );
}

/// The other addresses of [own]'s network (x.y.z.1 to .254, a /24 as on a
/// hotel or home Wi-Fi), or none when [own] is not a local address.
List<String> networkNeighbours(String own) {
  final parts = own.split('.');
  if (parts.length != 4 || !isLocalNetworkHost(own) || own.startsWith('127.')) {
    return const [];
  }
  final prefix = parts.take(3).join('.');
  return [
    for (var i = 1; i <= 254; i++)
      if ('$i' != parts[3]) '$prefix.$i',
  ];
}

// Mobile data and VPN interfaces: not the hotel's Wi-Fi.
final _notWifi = RegExp(r'^(rmnet|ccmni|pdp|v4-|dummy|tun|ppp|clat)');

/// Listens for the servers' announcements and scans the phone's network.
/// One UDP socket for the whole app, open while someone listens (the
/// Synchronisation screen, or the sync looking for its server's new
/// address).
class ServerDiscovery {
  final int port;

  /// How long a scanned address has to accept a connection.
  final Duration connectTimeout;
  ServerDiscovery({
    this.port = discoveryPort,
    this.connectTimeout = const Duration(milliseconds: 600),
  });

  RawDatagramSocket? _socket;
  late final _found = StreamController<FoundServer>.broadcast(
    onListen: _open,
    onCancel: _close,
  );

  /// Every announcement heard, as long as the subscription lasts. When the
  /// Wi-Fi drops them, nothing comes: [scan] still finds the server.
  Stream<FoundServer> watch() => _found.stream;

  /// The first announcement of server [id] within [within], or null.
  Future<FoundServer?> find(String id, Duration within) => watch()
      .where((s) => s.id == id)
      .cast<FoundServer?>()
      .first
      .timeout(within, onTimeout: () => null);

  /// This phone's addresses on a local network, one per network (Wi-Fi,
  /// emulator), mobile data left out.
  Future<List<String>> ownAddresses() async {
    final networks = <String, String>{};
    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        if (_notWifi.hasMatch(interface.name)) continue;
        for (final address in interface.addresses) {
          if (networkNeighbours(address.address).isEmpty) continue;
          final parts = address.address.split('.');
          networks.putIfAbsent(parts.take(3).join('.'), () => address.address);
        }
      }
    } on SocketException {
      // No network: nothing to scan.
    }
    return networks.values.take(3).toList();
  }

  /// Whether [host] accepts a connection on [port] within [connectTimeout].
  Future<bool> isOpen(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: connectTimeout);
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  /// The addresses of this phone's network where one of [ports] is open,
  /// as they answer: the candidates for GET /v1/health. [parallel]
  /// addresses are tried at once (254 addresses: about 2 seconds). Stops as
  /// soon as the subscription is cancelled.
  Stream<Uri> scan({
    Set<int> ports = const {defaultServerPort},
    int parallel = 64,
  }) {
    var stopped = false;
    late final StreamController<Uri> out;
    Future<void> run() async {
      try {
        final targets = [
          for (final own in await ownAddresses())
            for (final host in networkNeighbours(own))
              for (final port in ports) (host, port),
        ];
        var next = 0;
        Future<void> worker() async {
          while (!stopped && next < targets.length) {
            final (host, port) = targets[next++];
            if (await isOpen(host, port) && !stopped) {
              out.add(Uri(scheme: 'http', host: host, port: port));
            }
          }
        }

        await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
      } finally {
        if (!stopped) await out.close();
      }
    }

    out = StreamController<Uri>(
      onListen: () => unawaited(run()),
      onCancel: () => stopped = true,
    );
    return out.stream;
  }

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
      // Port taken or no network: the scan still finds the server.
    }
  }

  void _close() {
    _socket?.close();
    _socket = null;
  }
}
