import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Traduction via l'API gratuite MyMemory (aucune clé requise).
/// La langue de départ est détectée : un texte qui n'est pas en français est
/// traduit en français (un rapport écrit en anglais ou en arabe), un texte
/// en français est traduit en anglais.
/// Limites : 500 octets par requête (les textes plus longs sont découpés),
/// environ 5 000 mots par jour sans clé.
class TranslationService {
  TranslationService._();

  /// Les tests remplacent ce client.
  static http.Client Function() client = http.Client.new;

  static const _maxBytes = 450;
  static const _timeout = Duration(seconds: 10);

  /// Traduit [text] ; lève une [TranslationException] avec un message clair
  /// si le réseau, le quota ou l'API échoue.
  static Future<Translation> translate(String text) async {
    final input = text.trim();
    if (input.isEmpty) return Translation(text, 'fr', 'fr');
    final api = client();
    try {
      final chunks = _chunks(input);
      // La langue est détectée sur le premier morceau, avec le français pour
      // cible ; MyMemory refuse "fr → fr" : le texte est alors en français.
      final first = await _call(api, chunks.first, 'autodetect|fr');
      final from = first.distinct ? 'fr' : (first.detected ?? 'en');
      final to = from == 'fr' ? 'en' : 'fr';
      final parts = <String>[
        if (to == 'fr')
          first.text
        else
          (await _call(api, chunks.first, 'fr|en')).text,
      ];
      for (final chunk in chunks.skip(1)) {
        parts.add((await _call(api, chunk, '$from|$to')).text);
      }
      return Translation(parts.join(' '), from, to);
    } finally {
      api.close();
    }
  }

  static Future<_Answer> _call(
    http.Client api,
    String chunk,
    String langpair,
  ) async {
    final uri = Uri.https('api.mymemory.translated.net', '/get', {
      'q': chunk,
      'langpair': langpair,
    });
    final http.Response res;
    try {
      res = await api.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const TranslationException(
        'Le service de traduction ne répond pas. Réessayez.',
      );
    } on SocketException {
      throw const TranslationException(
        'Pas de connexion Internet : traduction impossible.',
      );
    } on http.ClientException {
      throw const TranslationException(
        'Pas de connexion Internet : traduction impossible.',
      );
    }
    // MyMemory répond en UTF-8 sans le dire dans l'en-tête : décoder les
    // octets, pas res.body.
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw TranslationException(
        'Réponse illisible du service de traduction (${res.statusCode}).',
      );
    }
    if (data is! Map) {
      throw const TranslationException('Traduction indisponible.');
    }
    final details = '${data['responseDetails'] ?? ''}';
    if (details.contains('DISTINCT LANGUAGES')) {
      return _Answer(chunk, 'fr', distinct: true);
    }
    final status = int.tryParse('${data['responseStatus']}') ?? res.statusCode;
    if (data['quotaFinished'] == true || status == 429) {
      throw const TranslationException(
        'Quota de traduction du jour atteint. Réessayez demain.',
      );
    }
    final response = data['responseData'];
    if (res.statusCode != 200 ||
        status != 200 ||
        response is! Map ||
        response['translatedText'] is! String) {
      throw TranslationException(
        details.isEmpty
            ? 'Traduction indisponible (${res.statusCode}).'
            : 'Traduction refusée : $details',
      );
    }
    final detected = response['detectedLanguage'];
    return _Answer(
      _decodeEntities(response['translatedText'] as String),
      detected is String ? detected.toLowerCase().split('-').first : null,
    );
  }

  /// Découpe aux espaces en morceaux de 450 octets au plus (MyMemory compte
  /// en octets : une lettre accentuée ou arabe en prend deux).
  static List<String> _chunks(String text) {
    final out = <String>[];
    var current = '';
    for (final word in text.split(RegExp(r'\s+'))) {
      final next = current.isEmpty ? word : '$current $word';
      if (utf8.encode(next).length <= _maxBytes) {
        current = next;
        continue;
      }
      if (current.isNotEmpty) out.add(current);
      current = word;
    }
    if (current.isNotEmpty) out.add(current);
    return out;
  }

  static String _decodeEntities(String s) => s
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

/// Une traduction, de la langue [from] vers [to] ("fr", "en", "ar"…).
class Translation {
  final String text, from, to;
  const Translation(this.text, this.from, this.to);

  /// « anglais → français », pour la ligne sous la traduction.
  String get label => '${languageName(from)} → ${languageName(to)}';
}

String languageName(String code) =>
    const {
      'ar': 'arabe',
      'de': 'allemand',
      'en': 'anglais',
      'es': 'espagnol',
      'fr': 'français',
      'it': 'italien',
      'pt': 'portugais',
      'tr': 'turc',
    }[code] ??
    code;

/// Pourquoi la traduction a échoué, en français pour l'utilisateur.
class TranslationException implements Exception {
  final String message;
  const TranslationException(this.message);
  @override
  String toString() => message;
}

class _Answer {
  final String text;
  final String? detected;
  final bool distinct;
  const _Answer(this.text, this.detected, {this.distinct = false});
}
