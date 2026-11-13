import 'dart:convert';

import 'package:http/http.dart' as http;

/// Traduction via l'API gratuite MyMemory (aucune clé requise).
/// Limites : ~500 caractères par requête, ~5000 caractères/jour sans clé.
class TranslationService {
  TranslationService._();

  static const _maxChunk = 450;

  /// Traduit [text] du français ([from]) vers l'anglais.
  /// Lève une exception si le réseau ou l'API échoue.
  static Future<String> toEnglish(String text, {String from = 'fr'}) async {
    final input = text.trim();
    if (input.isEmpty) return text;

    final parts = <String>[];
    for (final chunk in _chunks(input)) {
      parts.add(await _translateChunk(chunk, from));
    }
    return parts.join(' ');
  }

  static Future<String> _translateChunk(String chunk, String from) async {
    final uri = Uri.https('api.mymemory.translated.net', '/get', {
      'q': chunk,
      'langpair': '$from|en',
    });

    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw Exception('Traduction indisponible (${res.statusCode})');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final status = int.tryParse('${data['responseStatus']}') ?? 200;
    if (status != 200) {
      throw Exception('Traduction refusée (quota ou erreur API)');
    }
    return _decodeEntities(data['responseData']['translatedText'] as String);
  }

  /// Découpe en morceaux de <= 450 caractères, de préférence par phrase.
  static List<String> _chunks(String text) {
    final sentences = RegExp(r'[^.!?]+[.!?]*\s*')
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toList();

    final out = <String>[];
    var current = '';
    for (var s in sentences) {
      while (s.length > _maxChunk) {
        if (current.isNotEmpty) {
          out.add(current.trim());
          current = '';
        }
        out.add(s.substring(0, _maxChunk).trim());
        s = s.substring(_maxChunk);
      }
      if ((current + s).length > _maxChunk) {
        out.add(current.trim());
        current = s;
      } else {
        current += s;
      }
    }
    if (current.trim().isNotEmpty) out.add(current.trim());
    return out;
  }

  static String _decodeEntities(String s) => s
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
