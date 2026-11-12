import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_diagnosis_parser.dart';
import 'maintenance_config.dart';

/// Diagnostic IA d'une photo (API Messages de Claude, modèle avec vision).
///
/// Inactif tant qu'aucune clé n'est fournie (--dart-define=AI_API_KEY=...).
/// Ne lève jamais d'exception : renvoie null en cas d'échec.
class AiDiagnosisService {
  AiDiagnosisService._();

  static bool get isConfigured => MaintenanceConfig.aiEnabled;

  // Limite d'image : 10 Mo en base64 côté API → ~7 Mo en binaire.
  static const _maxImageBytes = 7 * 1024 * 1024;

  static const _systemPrompt = '''
Tu es un assistant de maintenance pour un hôtel. À partir d'une photo (et d'un indice éventuel donné par l'employé), identifie le problème technique visible.

Réponds UNIQUEMENT par un objet JSON, sans texte autour et sans balises de code, avec exactement ces clés :
- "is_maintenance_issue" : true ou false (false si la photo ne montre aucun problème de maintenance)
- "category" : une valeur parmi "climatisation", "plomberie", "electricite", "television", "autre"
- "priority" : "urgent" si danger pour les personnes ou dégât des eaux ou problème électrique actif ; "high" si la chambre est inutilisable ou le confort fortement dégradé ; sinon "normal"
- "title" : titre court en français, 60 caractères maximum
- "description" : 1 à 3 phrases factuelles en français décrivant ce que l'on voit, sans spéculer sur la cause
''';

  static Future<AiDiagnosis?> analyze({
    required Uint8List image,
    String? hint,
  }) async {
    if (!isConfigured) return null;
    if (image.lengthInBytes > _maxImageBytes) {
      debugPrint('Diagnostic IA : image trop lourde.');
      return null;
    }

    try {
      final uri = Uri.parse('${MaintenanceConfig.aiBaseUrl}/v1/messages');

      final headers = <String, String>{
        'content-type': 'application/json',
        'anthropic-version': '2023-06-01',
      };
      if (MaintenanceConfig.aiApiKey.isNotEmpty) {
        headers['x-api-key'] = MaintenanceConfig.aiApiKey;
      }
      // Appel direct depuis un navigateur : en-tête exigé par l'API (CORS).
      if (kIsWeb && MaintenanceConfig.usesAnthropicDirectly) {
        headers['anthropic-dangerous-direct-browser-access'] = 'true';
      }

      final cleanHint = hint?.trim() ?? '';
      final body = jsonEncode({
        'model': MaintenanceConfig.aiModel,
        'max_tokens': 2000,
        'system': _systemPrompt,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': detectImageMediaType(image),
                  'data': base64Encode(image),
                },
              },
              {
                'type': 'text',
                'text': cleanHint.isEmpty
                    ? 'Analyse cette photo.'
                    : "Analyse cette photo. Indice de l'employé : $cleanHint",
              },
            ],
          },
        ],
      });

      final res = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        debugPrint('Diagnostic IA : HTTP ${res.statusCode}');
        return null;
      }

      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final blocks = (data['content'] as List?) ?? const [];
      final text = blocks
          .whereType<Map>()
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'].toString())
          .join('\n');

      return parseAiDiagnosis(text);
    } catch (e) {
      debugPrint('Diagnostic IA impossible : $e');
      return null;
    }
  }
}
