import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/maintenance/models/intervention.dart';
import 'package:nova_paris/maintenance/services/ai_diagnosis_parser.dart';
import 'package:nova_paris/maintenance/services/maintenance_store.dart';
import 'package:nova_paris/maintenance/services/weather_maintenance_service.dart';
import 'package:nova_paris/maintenance/services/weather_rules.dart';
import 'package:nova_paris/shared/services/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Ayoub's advanced features: weather-driven preventive work, AI photo
// diagnosis (the reply parser) and translation.
void main() {
  final today = DateTime(2026, 7, 14, 9);

  group('weather rules', () {
    test('a mild day raises nothing', () {
      final days = [
        WeatherDay(
          date: today,
          tMax: 22,
          tMin: 12,
          rainMm: 2,
          gustKmh: 30,
          code: 3,
        ),
      ];
      expect(evaluateWeather(days, now: today), isEmpty);
    });

    test('heat, frost, storm and wind each raise one alert, worst day', () {
      final days = [
        WeatherDay(date: today, tMax: 31, tMin: 1, gustKmh: 75),
        WeatherDay(
          date: today.add(const Duration(days: 1)),
          tMax: 37,
          tMin: -4,
          rainMm: 20,
          code: 95,
        ),
      ];
      final alerts = {
        for (final a in evaluateWeather(days, now: today)) a.key: a,
      };
      expect(alerts.keys, {'heat', 'frost', 'storm', 'wind'});
      expect(alerts['heat']!.priority, InterventionPriority.urgent);
      expect(alerts['heat']!.description, contains('demain'));
      expect(alerts['frost']!.priority, InterventionPriority.high);
      expect(alerts['storm']!.category, InterventionCategory.plomberie);
      expect(alerts['wind']!.priority, InterventionPriority.high);
    });

    test('Open-Meteo daily block is read', () {
      final days = parseOpenMeteoDaily({
        'daily': {
          'time': ['2026-07-14', '2026-07-15'],
          'temperature_2m_max': [33.2, 28],
          'temperature_2m_min': [20, null],
          'precipitation_sum': [0, 12.5],
          'wind_gusts_10m_max': [40, 80],
          'weather_code': [1, 95],
        },
      });
      expect(days, hasLength(2));
      expect(days.first.tMax, 33.2);
      expect(days.last.tMin, isNull);
      expect(days.last.isStorm, isTrue);
    });
  });

  group('AI diagnosis reply', () {
    test('JSON inside text or code fences is read', () {
      final d = parseAiDiagnosis(
        'Voici :\n```json\n{"is_maintenance_issue": true, '
        '"category": "plomberie", "priority": "élevée", '
        '"title": "Fuite sous le lavabo", '
        '"description": "De l\'eau coule sous le lavabo."}\n```',
      )!;
      expect(d.isMaintenanceIssue, isTrue);
      expect(d.category, InterventionCategory.plomberie);
      expect(d.priority, InterventionPriority.high);
      expect(d.title, 'Fuite sous le lavabo');
    });

    test('a photo with no problem, or an unreadable reply', () {
      expect(
        parseAiDiagnosis('{"is_maintenance_issue": false}')!.isMaintenanceIssue,
        isFalse,
      );
      expect(parseAiDiagnosis('Je ne peux pas analyser.'), isNull);
    });

    test('image type is detected from its first bytes', () {
      expect(
        detectImageMediaType(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])),
        'image/png',
      );
      expect(
        detectImageMediaType(Uint8List.fromList([0xFF, 0xD8, 0xFF])),
        'image/jpeg',
      );
    });
  });

  group('database and weather service', () {
    late Directory dir;
    late AppDatabase database;
    late MaintenanceStore store;
    setUpAll(sqfliteFfiInit);
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('nova_maint_features_');
      database = await AppDatabase.open(
        schemas: [maintenanceSchema],
        factory: databaseFactoryFfi,
        path: p.join(dir.path, 'nova.db'),
      );
      store = MaintenanceStore(database.database);
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() async {
      await database.close();
      await dir.delete(recursive: true);
    });

    final heatwave = [WeatherDay(date: today, tMax: 36, tMin: 22)];

    test(
      'the forecast creates preventive work once, not on every check',
      () async {
        expect(
          await WeatherMaintenanceService.runIfDue(
            store,
            fetch: () async => heatwave,
          ),
          1,
        );
        final alert = (await store.active()).single;
        expect(alert.isWeatherAlert, isTrue);
        expect(alert.roomLabel, "Tout l'hôtel");
        expect(alert.reporterLabel, 'Alerte météo automatique');
        expect(alert.priority, InterventionPriority.urgent);

        // Not due again for 3 hours.
        expect(
          await WeatherMaintenanceService.runIfDue(
            store,
            fetch: () async => heatwave,
          ),
          0,
        );
        // Due, but the same alert is still open: no duplicate.
        SharedPreferences.setMockInitialValues({});
        expect(
          await WeatherMaintenanceService.runIfDue(
            store,
            fetch: () async => heatwave,
          ),
          0,
        );
        // Resolved less than 48 h ago: still no duplicate.
        await store.markResolved(alert.id);
        SharedPreferences.setMockInitialValues({});
        expect(
          await WeatherMaintenanceService.runIfDue(
            store,
            fetch: () async => heatwave,
          ),
          0,
        );
      },
    );

    test('no network: nothing created, nothing thrown', () async {
      expect(
        await WeatherMaintenanceService.runIfDue(
          store,
          fetch: () async => throw const SocketException('offline'),
        ),
        0,
      );
      expect(await store.active(), isEmpty);
    });

    test('a version 1 database keeps its reports as manual ones', () async {
      final path = p.join(dir.path, 'v1.db');
      final v1 = await AppDatabase.open(
        schemas: [
          ModuleSchema(
            module: 'maintenance',
            version: 1,
            migrate: (tx, from, to) => maintenanceSchema.migrate(tx, 0, 1),
          ),
        ],
        factory: databaseFactoryFfi,
        path: path,
      );
      await v1.database.insert('maintenance_interventions', {
        'title': 'Clim',
        'room': '305',
        'created_at': today.toIso8601String(),
        'updated_at': today.toIso8601String(),
      });
      await v1.close();

      final v2 = await AppDatabase.open(
        schemas: [maintenanceSchema],
        factory: databaseFactoryFfi,
        path: path,
      );
      final old = (await MaintenanceStore(v2.database).active()).single;
      expect(old.source, 'manual');
      expect(old.roomLabel, 'Ch. 305');
      expect(await v2.versionOf('maintenance'), 2);
      await v2.close();
    });
  });
}
