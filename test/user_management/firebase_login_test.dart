import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_paris/user_management/accounts/services/auth_service.dart';
import 'package:nova_paris/user_management/accounts/services/database_helper.dart';
import 'package:nova_paris/user_management/accounts/services/firebase_auth_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Firebase Authentication as the app sees it: e-mail → password.
class _FakeFirebase {
  final accounts = <String, String>{};
  final resetsSent = <String>[];
  bool offline = false;

  http.Client client() => MockClient((request) async {
    if (offline) throw const SocketException('no network');
    final body = jsonDecode(request.body) as Map<String, Object?>;
    final email = body['email'] as String;
    http.Response error(String code) => http.Response(
      jsonEncode({
        'error': {'message': code},
      }),
      400,
    );
    switch (request.url.path) {
      case '/v1/accounts:signInWithPassword':
        return accounts[email] == body['password']
            ? http.Response('{}', 200)
            : error('INVALID_LOGIN_CREDENTIALS');
      case '/v1/accounts:signUp':
        if (accounts.containsKey(email)) return error('EMAIL_EXISTS');
        accounts[email] = body['password'] as String;
        return http.Response('{}', 200);
      case '/v1/accounts:sendOobCode':
        resetsSent.add(email);
        return http.Response('{}', 200);
    }
    return http.Response('', 404);
  });

  /// The user clicks the link in the e-mail and chooses a new password.
  void resetFromEmail(String email, String newPassword) =>
      accounts[email] = newPassword;
}

void main() {
  late _FakeFirebase firebase;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Its own folder: accounts_test.dart rewrites nova_paris.db meanwhile.
    final dir = await Directory.systemTemp.createTemp('nova_firebase_login_');
    await databaseFactory.setDatabasesPath(dir.path);
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    firebase = _FakeFirebase();
    FirebaseAuthApi.apiKey = 'test-key';
    FirebaseAuthApi.client = firebase.client;
  });

  Future<void> register(String email, String password) async {
    expect(
      await AuthService.register(
        fullName: email,
        displayName: email.split('@').first,
        password: password,
        role: 'staff',
      ),
      isTrue,
    );
  }

  test('a new account is created in Firebase too', () async {
    await register('new@firebase.test', 'first-pass');
    expect(firebase.accounts['new@firebase.test'], 'first-pass');
    final row = await DatabaseHelper.instance.getUserByEmail(
      'new@firebase.test',
    );
    expect(row!['firebase_linked'], 1);
  });

  test('after a reset by e-mail, the new password opens the app and the '
      'old one no longer does, also offline', () async {
    await register('reset@firebase.test', 'old-pass');

    expect(
      await AuthService.sendFirebaseResetEmail('reset@firebase.test'),
      isNull,
    );
    expect(firebase.resetsSent, ['reset@firebase.test']);
    firebase.resetFromEmail('reset@firebase.test', 'new-pass');

    expect(await AuthService.login('reset@firebase.test', 'old-pass'), isNull);
    final user = await AuthService.login('reset@firebase.test', 'new-pass');
    expect(user?.fullName, 'reset@firebase.test');

    firebase.offline = true;
    expect(
      await AuthService.login('reset@firebase.test', 'new-pass'),
      isNotNull,
      reason: 'the new password was kept on the phone',
    );
    expect(await AuthService.login('reset@firebase.test', 'old-pass'), isNull);
  });

  test('offline, the phone decides with the password it has', () async {
    firebase.offline = true;
    await register('offline@firebase.test', 'pass-1');
    expect(firebase.accounts, isEmpty);
    expect(
      await AuthService.login('offline@firebase.test', 'pass-1'),
      isNotNull,
    );
    expect(await AuthService.login('offline@firebase.test', 'wrong'), isNull);

    // Back online: the first login creates the Firebase twin.
    firebase.offline = false;
    expect(
      await AuthService.login('offline@firebase.test', 'pass-1'),
      isNotNull,
    );
    expect(firebase.accounts['offline@firebase.test'], 'pass-1');
  });

  test('an account already in Firebase with another password still opens '
      'with the phone password until Firebase accepts one', () async {
    firebase.accounts['console@firebase.test'] = 'set-in-console';
    await register('console@firebase.test', 'phone-pass');
    final row = await DatabaseHelper.instance.getUserByEmail(
      'console@firebase.test',
    );
    expect(row!['firebase_linked'], 0);
    expect(
      await AuthService.login('console@firebase.test', 'phone-pass'),
      isNotNull,
    );

    firebase.resetFromEmail('console@firebase.test', 'after-reset');
    expect(
      await AuthService.login('console@firebase.test', 'after-reset'),
      isNotNull,
    );
    expect(
      await AuthService.login('console@firebase.test', 'phone-pass'),
      isNull,
      reason: 'linked now: Firebase decides',
    );
  });

  test('without a key in the build, everything stays on the phone', () async {
    FirebaseAuthApi.apiKey = '';
    await register('nokey@firebase.test', 'pass');
    expect(firebase.accounts, isEmpty);
    expect(await AuthService.login('nokey@firebase.test', 'pass'), isNotNull);
    expect(
      await AuthService.sendFirebaseResetEmail('nokey@firebase.test'),
      contains('non configurée'),
    );
  });
}
