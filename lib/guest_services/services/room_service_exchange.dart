import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

class RoomServiceExchange {
  RoomServiceExchange(this.database);

  final Database database;

  Future<({double rate, String date, bool cached})> load({
    String currency = 'TND',
  }) async {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) || currency == 'EUR') {
      throw ArgumentError.value(currency, 'currency');
    }
    final saved = await database.query(
      'guest_services_currency_rates',
      where: 'currency = ?',
      whereArgs: [currency],
    );
    final row = saved.firstOrNull;
    if (row != null) {
      final fetched = DateTime.parse(row['fetched_at'] as String);
      if (DateTime.now().difference(fetched) < const Duration(hours: 6)) {
        return (
          rate: row['rate'] as double,
          date: row['rate_date'] as String,
          cached: true,
        );
      }
    }
    try {
      final response = await http
          .get(Uri.https('api.frankfurter.dev', '/v2/rate/EUR/$currency'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw StateError('Taux indisponible.');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rate = (data['rate'] as num).toDouble();
      final date = data['date'] as String;
      if (!rate.isFinite || rate <= 0 || DateTime.tryParse(date) == null) {
        throw StateError('Taux invalide.');
      }
      await database.insert(
        'guest_services_currency_rates',
        {
          'currency': currency,
          'rate': rate,
          'rate_date': date,
          'fetched_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return (rate: rate, date: date, cached: false);
    } catch (_) {
      if (row == null) rethrow;
      return (
        rate: row['rate'] as double,
        date: row['rate_date'] as String,
        cached: true,
      );
    }
  }
}
