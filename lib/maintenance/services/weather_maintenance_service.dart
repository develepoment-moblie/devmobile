import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'maintenance_config.dart';
import 'maintenance_store.dart';
import 'weather_rules.dart';

/// Maintenance prédictive : lit les prévisions Open-Meteo et crée
/// automatiquement des interventions préventives (canicule, gel, orage, vent).
class WeatherMaintenanceService {
  WeatherMaintenanceService._();

  static const _lastCheckKey = 'maintenance_weather_last_check';
  static const _room = "Tout l'hôtel";

  /// Vérifie la météo si le dernier contrôle date de plus de 3 h.
  /// Renvoie le nombre d'interventions créées. N'échoue jamais : en cas de
  /// problème réseau, il renvoie 0 et l'écran continue normalement.
  /// [fetch] replaces Open-Meteo in tests.
  static Future<int> runIfDue(
    MaintenanceStore store, {
    Future<List<WeatherDay>> Function()? fetch,
  }) async {
    if (!MaintenanceConfig.weatherEnabled) return 0;

    try {
      final prefs = await SharedPreferences.getInstance();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final last = prefs.getInt(_lastCheckKey) ?? 0;
      final due =
          MaintenanceConfig.weatherDemo ||
          nowMs - last >= MaintenanceConfig.weatherCheckEvery.inMilliseconds;
      if (!due) return 0;

      final days = MaintenanceConfig.weatherDemo
          ? demoForecast()
          : await (fetch ?? _fetchForecast)();

      var created = 0;
      for (final alert in evaluateWeather(days)) {
        final exists = await store.hasActiveOrRecentAlert(
          source: 'weather',
          sourceKey: alert.key,
        );
        if (exists) continue;

        await store.create(
          title: alert.title,
          room: _room,
          category: alert.category,
          priority: alert.priority,
          description: alert.description,
          source: 'weather',
          sourceKey: alert.key,
        );
        created++;
      }

      await prefs.setInt(_lastCheckKey, nowMs);
      return created;
    } catch (e) {
      debugPrint('Contrôle météo impossible : $e');
      return 0;
    }
  }

  static Future<List<WeatherDay>> _fetchForecast() async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': MaintenanceConfig.hotelLatitude.toString(),
      'longitude': MaintenanceConfig.hotelLongitude.toString(),
      'daily':
          'weather_code,temperature_2m_max,temperature_2m_min,'
          'precipitation_sum,wind_gusts_10m_max',
      'timezone': 'auto',
      'forecast_days': MaintenanceConfig.forecastDays.toString(),
    });

    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Open-Meteo HTTP ${res.statusCode}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return parseOpenMeteoDaily(json);
  }
}
