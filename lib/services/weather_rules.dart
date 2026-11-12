import '../models/intervention.dart';
import 'maintenance_config.dart';

/// Prévision météo d'une journée (unités : °C, mm, km/h).
class WeatherDay {
  final DateTime date;
  final double? tMax;
  final double? tMin;
  final double? rainMm;
  final double? gustKmh;
  final int? code; // code météo WMO (95, 96, 99 = orage)

  const WeatherDay({
    required this.date,
    this.tMax,
    this.tMin,
    this.rainMm,
    this.gustKmh,
    this.code,
  });

  bool get isStorm => code == 95 || code == 96 || code == 99;
}

/// Intervention préventive à créer suite à une prévision.
class WeatherAlert {
  /// heat | frost | storm | wind (sert à éviter les doublons)
  final String key;
  final InterventionCategory category;
  final InterventionPriority priority;
  final String title;
  final String description;

  const WeatherAlert({
    required this.key,
    required this.category,
    required this.priority,
    required this.title,
    required this.description,
  });
}

/// Convertit la réponse JSON d'Open-Meteo (bloc "daily") en liste de jours.
List<WeatherDay> parseOpenMeteoDaily(Map<String, dynamic> json) {
  final daily = json['daily'];
  if (daily is! Map) return const [];

  final times = (daily['time'] as List?) ?? const [];

  double? at(String name, int i) {
    final col = daily[name];
    if (col is List && i < col.length && col[i] is num) {
      return (col[i] as num).toDouble();
    }
    return null;
  }

  final days = <WeatherDay>[];
  for (var i = 0; i < times.length; i++) {
    final date = DateTime.tryParse(times[i].toString());
    if (date == null) continue;
    days.add(WeatherDay(
      date: date,
      tMax: at('temperature_2m_max', i),
      tMin: at('temperature_2m_min', i),
      rainMm: at('precipitation_sum', i),
      gustKmh: at('wind_gusts_10m_max', i),
      code: at('weather_code', i)?.round(),
    ));
  }
  return days;
}

/// Règles de maintenance prédictive : transforme les prévisions en alertes.
/// Pour chaque type de risque, on retient le pire jour de la période.
List<WeatherAlert> evaluateWeather(List<WeatherDay> days, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final alerts = <WeatherAlert>[];

  // ---------- Forte chaleur → climatisations ----------
  final hot = _worst(
    days,
    (d) => d.tMax != null && d.tMax! >= MaintenanceConfig.heatC,
    (d) => d.tMax!,
  );
  if (hot != null) {
    alerts.add(WeatherAlert(
      key: 'heat',
      category: InterventionCategory.climatisation,
      priority: hot.tMax! >= MaintenanceConfig.heatUrgentC
          ? InterventionPriority.urgent
          : InterventionPriority.high,
      title: 'Contrôle préventif des climatisations',
      description:
          'Forte chaleur prévue ${_dayLabel(hot.date, today)} (${hot.tMax!.round()} °C max). '
          'Vérifier le bon fonctionnement des climatisations (filtres, groupes froids, '
          'thermostats) avant l\'arrivée des clients.',
    ));
  }

  // ---------- Gel → chauffage et canalisations ----------
  final cold = _worst(
    days,
    (d) => d.tMin != null && d.tMin! <= MaintenanceConfig.frostC,
    (d) => -d.tMin!,
  );
  if (cold != null) {
    alerts.add(WeatherAlert(
      key: 'frost',
      category: InterventionCategory.plomberie,
      priority: cold.tMin! <= MaintenanceConfig.frostHighC
          ? InterventionPriority.high
          : InterventionPriority.normal,
      title: 'Contrôle préventif du chauffage et des canalisations',
      description:
          'Gel prévu ${_dayLabel(cold.date, today)} (${cold.tMin!.round()} °C min). '
          'Vérifier le chauffage et protéger les canalisations et robinets extérieurs.',
    ));
  }

  // ---------- Orage / fortes pluies → fuites et étanchéité ----------
  final wet = _worst(
    days,
    (d) => d.isStorm || (d.rainMm != null && d.rainMm! >= MaintenanceConfig.rainMm),
    (d) => (d.rainMm ?? 0) + (d.isStorm ? 100 : 0),
  );
  if (wet != null) {
    final rain = wet.rainMm ?? 0;
    final what = wet.isStorm
        ? 'Orage prévu ${_dayLabel(wet.date, today)}'
            '${rain > 0 ? ' (${rain.round()} mm de pluie)' : ''}'
        : 'Fortes pluies prévues ${_dayLabel(wet.date, today)} (${rain.round()} mm)';
    alerts.add(WeatherAlert(
      key: 'storm',
      category: InterventionCategory.plomberie,
      priority: (wet.isStorm || rain >= MaintenanceConfig.rainHighMm)
          ? InterventionPriority.high
          : InterventionPriority.normal,
      title: 'Contrôle préventif des fuites et de l\'étanchéité',
      description:
          '$what. Vérifier l\'étanchéité (toiture, fenêtres, terrasses) et les évacuations d\'eau.',
    ));
  }

  // ---------- Vent fort → fenêtres et volets ----------
  final windy = _worst(
    days,
    (d) => d.gustKmh != null && d.gustKmh! >= MaintenanceConfig.windKmh,
    (d) => d.gustKmh!,
  );
  if (windy != null) {
    alerts.add(WeatherAlert(
      key: 'wind',
      category: InterventionCategory.autre,
      priority: windy.gustKmh! >= MaintenanceConfig.windUrgentKmh
          ? InterventionPriority.urgent
          : InterventionPriority.high,
      title: 'Contrôle préventif des fenêtres et volets',
      description:
          'Rafales jusqu\'à ${windy.gustKmh!.round()} km/h prévues ${_dayLabel(windy.date, today)}. '
          'Vérifier la fixation des volets, fenêtres, stores et du mobilier extérieur.',
    ));
  }

  return alerts;
}

/// Fausses prévisions pour la démonstration (WEATHER_DEMO=true).
List<WeatherDay> demoForecast({DateTime? now}) {
  final t = now ?? DateTime.now();
  final d0 = DateTime(t.year, t.month, t.day);
  return [
    WeatherDay(date: d0, tMax: 36, tMin: 22, rainMm: 0, gustKmh: 25, code: 1),
    WeatherDay(
        date: d0.add(const Duration(days: 1)),
        tMax: 29,
        tMin: 19,
        rainMm: 24,
        gustKmh: 55,
        code: 95),
    WeatherDay(
        date: d0.add(const Duration(days: 2)),
        tMax: 27,
        tMin: 18,
        rainMm: 2,
        gustKmh: 30,
        code: 3),
  ];
}

WeatherDay? _worst(
  List<WeatherDay> days,
  bool Function(WeatherDay) trigger,
  double Function(WeatherDay) severity,
) {
  WeatherDay? best;
  for (final d in days) {
    if (!trigger(d)) continue;
    if (best == null || severity(d) > severity(best)) best = d;
  }
  return best;
}

String _dayLabel(DateTime d, DateTime now) {
  final a = DateTime.utc(d.year, d.month, d.day);
  final b = DateTime.utc(now.year, now.month, now.day);
  final diff = a.difference(b).inDays;
  if (diff == 0) return "aujourd'hui";
  if (diff == 1) return 'demain';
  String two(int n) => n.toString().padLeft(2, '0');
  return 'le ${two(d.day)}/${two(d.month)}';
}
