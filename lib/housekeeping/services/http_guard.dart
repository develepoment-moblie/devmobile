import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// What the module's web calls (sync server, Open Food/Beauty Facts,
// MyMemory) do the same way: a timeout or no connection becomes the
// caller's own message, and an answer is read as a JSON object.

enum NetworkFailure { timeout, offline }

/// Sends [request] within [timeout]; a timeout or no connection is handed
/// to [fail], which throws the caller's own error.
Future<http.Response> guardedRequest(
  Future<http.Response> Function() request, {
  required Duration timeout,
  required Never Function(NetworkFailure failure) fail,
}) async {
  try {
    return await request().timeout(timeout);
  } on TimeoutException {
    fail(NetworkFailure.timeout);
  } on SocketException {
    fail(NetworkFailure.offline);
  } on http.ClientException {
    fail(NetworkFailure.offline);
  }
}

/// The JSON object in [response] (UTF-8), or null when it is not one.
Map<String, dynamic>? jsonObject(http.Response response) {
  try {
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    return value is Map ? value.cast<String, dynamic>() : null;
  } on FormatException {
    return null;
  }
}
