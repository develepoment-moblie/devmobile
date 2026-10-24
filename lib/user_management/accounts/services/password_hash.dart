import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

// Passwords and security answers are never stored in plain text:
// PBKDF2-HMAC-SHA256 with a random salt, stored as
// "pbkdf2$<iterations>$<salt>$<hash>" (base64).
const _iterations = 10000;
final _random = Random.secure();

bool isHashed(String? value) => value?.startsWith(r'pbkdf2$') ?? false;

Uint8List _derive(String secret, Uint8List salt, int iterations) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, iterations, 32));
  return kdf.process(Uint8List.fromList(utf8.encode(secret)));
}

String hashSecret(String secret) {
  final salt = Uint8List.fromList(
    List<int>.generate(16, (_) => _random.nextInt(256)),
  );
  final hash = _derive(secret, salt, _iterations);
  return 'pbkdf2\$$_iterations\$${base64Encode(salt)}\$${base64Encode(hash)}';
}

bool verifySecret(String secret, String? stored) {
  if (!isHashed(stored)) return false;
  final parts = stored!.split(r'$');
  if (parts.length != 4) return false;
  final iterations = int.tryParse(parts[1]) ?? 0;
  final expected = base64Decode(parts[3]);
  final actual = _derive(secret, base64Decode(parts[2]), iterations);
  if (actual.length != expected.length) return false;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual[i] ^ expected[i];
  }
  return diff == 0;
}
