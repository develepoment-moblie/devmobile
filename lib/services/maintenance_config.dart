/// Réglages des fonctions avancées du module Maintenance.
///
/// Les valeurs sensibles se passent à la compilation, jamais dans le code :
///   flutter run --dart-define=AI_API_KEY=sk-ant-...
///   flutter run --dart-define=WEATHER_DEMO=true     (simule une canicule + un orage)
class MaintenanceConfig {
  MaintenanceConfig._();

  // ============ HÔTEL (Paris) ============
  static const double hotelLatitude = 48.8566;
  static const double hotelLongitude = 2.3522;

  // ============ MÉTÉO — Open-Meteo (gratuit, sans clé) ============
  static const bool weatherEnabled =
      bool.fromEnvironment('WEATHER_ENABLED', defaultValue: true);

  /// Mode démonstration : fausses prévisions (canicule + orage).
  static const bool weatherDemo =
      bool.fromEnvironment('WEATHER_DEMO', defaultValue: false);

  /// Délai minimum entre deux appels à l'API météo.
  static const Duration weatherCheckEvery = Duration(hours: 3);
  static const int forecastDays = 3;

  /// Après résolution d'une alerte, on ne la recrée pas avant ce délai.
  static const Duration alertCooldown = Duration(hours: 48);

  // Seuils (°C, mm, km/h)
  static const double heatC = 0;
  static const double heatUrgentC = 35;
  static const double frostC = 0;
  static const double frostHighC = -3;
  static const double rainMm = 15;
  static const double rainHighMm = 30;
  static const double windKmh = 70;
  static const double windUrgentKmh = 100;

  // ============ IA — diagnostic par photo (API Claude) ============
  static const String aiApiKey = String.fromEnvironment('AI_API_KEY');

  /// Pour passer par votre propre serveur intermédiaire (recommandé en
  /// production) : --dart-define=AI_BASE_URL=https://votre-serveur.exemple
  static const String aiBaseUrl = String.fromEnvironment(
    'AI_BASE_URL',
    defaultValue: 'https://api.anthropic.com',
  );
  static const String aiModel =
      String.fromEnvironment('AI_MODEL', defaultValue: 'claude-haiku-5-5');

  static bool get usesAnthropicDirectly =>
      aiBaseUrl == 'https://api.anthropic.com';

  /// La fonction IA est inactive tant qu'aucune clé (ou serveur) n'est fourni.
  static bool get aiEnabled => aiApiKey.isNotEmpty || !usesAnthropicDirectly;
}
