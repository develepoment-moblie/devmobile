import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// What Firebase answered about an e-mail and password.
enum FirebaseAnswer {
  /// Firebase accepted it.
  accepted,

  /// Firebase refused it (wrong password, unknown or disabled account).
  refused,

  /// The account already exists in Firebase (sign-up only).
  exists,

  /// No key in this build, no network, or Firebase did not answer in time:
  /// the phone decides on its own.
  unavailable,
}

/// Firebase Authentication through its REST API. The key is given at build
/// time, never written in the code:
///   flutter build apk --dart-define=FIREBASE_API_KEY=...
class FirebaseAuthApi {
  FirebaseAuthApi._();

  static const _buildKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _timeout = Duration(seconds: 8);

  /// Tests replace these.
  static String apiKey = _buildKey;
  static http.Client Function() client = http.Client.new;

  static bool get isConfigured => apiKey.isNotEmpty;

  /// Checks an e-mail and password with Firebase.
  static Future<FirebaseAnswer> signIn(String email, String password) async {
    final (status, error) = await _post('accounts:signInWithPassword', {
      'email': email.trim(),
      'password': password,
      'returnSecureToken': true,
    });
    if (status == null) return FirebaseAnswer.unavailable;
    if (status == 200) return FirebaseAnswer.accepted;
    return _refusals.contains(_code(error))
        ? FirebaseAnswer.refused
        : FirebaseAnswer.unavailable;
  }

  /// Creates the Firebase twin of an account, so the reset e-mail can reach it.
  static Future<FirebaseAnswer> signUp(String email, String password) async {
    final (status, error) = await _post('accounts:signUp', {
      'email': email.trim(),
      'password': password,
      'returnSecureToken': true,
    });
    if (status == null) return FirebaseAnswer.unavailable;
    if (status == 200) return FirebaseAnswer.accepted;
    if (_code(error) == 'EMAIL_EXISTS') return FirebaseAnswer.exists;
    return FirebaseAnswer.unavailable;
  }

  /// Sends the reset e-mail. Null on success, otherwise the message to show.
  static Future<String?> sendPasswordReset(String email) async {
    if (!isConfigured) {
      return 'Réinitialisation par e-mail non configurée (clé Firebase absente).';
    }
    final (status, error) = await _post('accounts:sendOobCode', {
      'requestType': 'PASSWORD_RESET',
      'email': email.trim(),
    });
    if (status == null) return 'Erreur réseau. Vérifiez votre connexion.';
    if (status == 200) return null;
    return switch (_code(error)) {
      'EMAIL_NOT_FOUND' => 'Aucun compte n’existe avec cet e-mail.',
      'INVALID_EMAIL' => 'L’adresse e-mail est invalide.',
      'TOO_MANY_ATTEMPTS_TRY_LATER' => 'Trop d’essais. Réessayez plus tard.',
      final code => 'Erreur : $code',
    };
  }

  // Answers that mean "these credentials are wrong", not "Firebase is down".
  static const _refusals = {
    'INVALID_LOGIN_CREDENTIALS',
    'INVALID_PASSWORD',
    'EMAIL_NOT_FOUND',
    'USER_DISABLED',
    'INVALID_EMAIL',
  };

  // The code is the first word: "TOO_MANY_ATTEMPTS_TRY_LATER : ...".
  static String _code(String? message) =>
      (message ?? '').split(RegExp(r'[\s:]')).first;

  /// (status, error message), or (null, null) when there is no answer.
  static Future<(int?, String?)> _post(
    String method,
    Map<String, Object?> body,
  ) async {
    if (!isConfigured) return (null, null);
    final c = client();
    try {
      final response = await c
          .post(
            Uri.https('identitytoolkit.googleapis.com', '/v1/$method', {
              'key': apiKey,
            }),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) return (200, null);
      String? message;
      try {
        message =
            (jsonDecode(response.body) as Map)['error']['message'] as String?;
      } catch (_) {}
      return (response.statusCode, message);
    } catch (_) {
      return (null, null);
    } finally {
      c.close();
    }
  }
}
