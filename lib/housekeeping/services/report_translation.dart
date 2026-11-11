import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_exception.dart';

// Translates a problem report into French with MyMemory (free, no key, a
// daily quota): an agent writes in Arabic or English, the supervisor reads
// it in French. The language is detected by MyMemory.
//   GET https://api.mymemory.translated.net/get?q=<text>&langpair=autodetect|fr
// Only the report's text leaves the phone, never names or photos. Nothing is
// saved: the original stays the reference.

/// A translation into French, and the language it was translated from
/// (a code such as "en", or null when unknown).
class Translation {
  final String text;
  final String? from;
  const Translation(this.text, this.from);

  bool get alreadyFrench => from == 'fr';

  /// "anglais", "arabe"… for "Traduction automatique (anglais → français)".
  String get fromLabel => languageNames[from] ?? from ?? 'langue détectée';
}

const languageNames = {
  'ar': 'arabe',
  'de': 'allemand',
  'en': 'anglais',
  'es': 'espagnol',
  'fr': 'français',
  'it': 'italien',
  'nl': 'néerlandais',
  'pt': 'portugais',
  'ru': 'russe',
  'tr': 'turc',
  'zh': 'chinois',
};

/// MyMemory takes 500 bytes per request: longer texts are cut at word
/// boundaries.
List<String> translationChunks(String text, {int maxBytes = 450}) {
  final chunks = <String>[];
  var current = '';
  for (final word in text.trim().split(RegExp(r'\s+'))) {
    final next = current.isEmpty ? word : '$current $word';
    if (utf8.encode(next).length <= maxBytes) {
      current = next;
      continue;
    }
    if (current.isNotEmpty) chunks.add(current);
    current = word;
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

String _unescape(String text) => text
    .replaceAll('&#39;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

class ReportTranslator {
  final http.Client _client;
  final Duration timeout;
  ReportTranslator({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  Future<Translation> toFrench(String text) async {
    final parts = translationChunks(text);
    if (parts.isEmpty) return const Translation('', 'fr');
    final out = <String>[];
    String? from;
    for (final part in parts) {
      final (translated, detected) = await _one(part);
      out.add(translated);
      from ??= detected;
    }
    return Translation(from == 'fr' ? text.trim() : out.join(' '), from);
  }

  Future<(String, String?)> _one(String text) async {
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.https('api.mymemory.translated.net', '/get', {
              'q': text,
              'langpair': 'autodetect|fr',
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AppServiceException(
        'Le service de traduction ne répond pas. Réessayez.',
      );
    } on SocketException {
      throw const AppServiceException(
        'Pas de connexion Internet : traduction impossible.',
      );
    } on http.ClientException {
      throw const AppServiceException(
        'Pas de connexion Internet : traduction impossible.',
      );
    }
    final Map<String, dynamic> json;
    try {
      json = (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
          .cast<String, dynamic>();
    } on FormatException {
      throw const AppServiceException('Traduction indisponible.');
    }
    final status = json['responseStatus'];
    // A text already in French: MyMemory refuses "fr → fr".
    if ('${json['responseDetails']}'.contains('DISTINCT LANGUAGES')) {
      return (text, 'fr');
    }
    if (json['quotaFinished'] == true || status == 429 || status == '429') {
      throw const AppServiceException(
        'Quota de traduction du jour atteint. Réessayez demain.',
      );
    }
    final data = json['responseData'];
    if (response.statusCode != 200 ||
        (status != 200 && status != '200') ||
        data is! Map ||
        data['translatedText'] is! String) {
      throw const AppServiceException('Traduction indisponible.');
    }
    final detected = data['detectedLanguage'];
    return (
      _unescape(data['translatedText'] as String),
      detected is String ? detected.toLowerCase().split('-').first : null,
    );
  }

  void close() => _client.close();
}
