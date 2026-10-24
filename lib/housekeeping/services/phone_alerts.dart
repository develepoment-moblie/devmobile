import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/hotel_data.dart';
import 'notification_rules.dart';

/// Shows housekeeping notifications as phone notifications (Android).
/// Only notifications that arrive while the app runs are shown; the ones
/// already there when the workspace opens are not repeated.
abstract interface class PhoneAlerts {
  /// Sets up the channel and asks Android for permission once.
  Future<void> prepare();
  Future<void> show(HotelNotification notification);
}

/// Late-cleaning alerts handed to Android in advance, so they appear even
/// when the app is closed. [sync] replaces the whole planned set.
abstract interface class LateAlarms {
  Future<void> sync(List<LateAlarm> alarms);
}

/// One phone notification per room for lateness: the alert Android
/// delivers and the one the app shows replace each other, never both.
int lateAlertId(String roomNumber) =>
    0x40000000 + (roomNumber.hashCode & 0x0fffffff);

const _lateTitle = 'Nettoyage en retard';
const _latePayload = 'late:';

class LocalPhoneAlerts implements PhoneAlerts, LateAlarms {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;
  int _next = 0;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'housekeeping',
      'Ménage',
      channelDescription: 'Attributions, validations, stock et objets trouvés.',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<bool> _init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      tz_data.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      return true;
    } catch (error) {
      debugPrint(
        'housekeeping: notifications du téléphone indisponibles ($error)',
      );
      return false;
    }
  }

  @override
  Future<void> prepare() => _ready ??= _init();

  @override
  Future<void> show(HotelNotification n) async {
    if (!await (_ready ??= _init())) return;
    try {
      await _plugin.show(
        id: n.category == 'late' ? lateAlertId(n.roomNumber) : _next++,
        title: n.title,
        body: n.message,
        notificationDetails: _details,
      );
    } catch (error) {
      debugPrint('housekeeping: notification non affichée ($error)');
    }
  }

  @override
  Future<void> sync(List<LateAlarm> alarms) async {
    if (!await (_ready ??= _init())) return;
    try {
      for (final pending in await _plugin.pendingNotificationRequests()) {
        if (pending.payload?.startsWith(_latePayload) == true) {
          await _plugin.cancel(id: pending.id);
        }
      }
      for (final a in alarms) {
        await _plugin.zonedSchedule(
          id: lateAlertId(a.roomNumber),
          title: _lateTitle,
          body:
              'Chambre ${a.roomNumber} : ${a.agentName} dépasse le temps prévu (${a.limitMinutes} min).',
          // An instant in UTC: no need to know the phone's time zone name.
          scheduledDate: tz.TZDateTime.from(a.at.toUtc(), tz.UTC),
          notificationDetails: _details,
          // Approximate time: no "alarms and reminders" permission needed.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: '$_latePayload${a.roomNumber}',
        );
      }
    } catch (error) {
      debugPrint('housekeeping: alerte programmée impossible ($error)');
    }
  }
}

/// Remembers which notifications were already seen and alerts the new ones.
class AlertWatcher {
  final PhoneAlerts alerts;
  final Set<String> _seen = {};
  bool _primed = false;
  AlertWatcher(this.alerts);

  void check(List<HotelNotification> visible) {
    if (!_primed) {
      _seen.addAll(visible.map((n) => n.id));
      _primed = true;
      alerts.prepare();
      return;
    }
    for (final n in visible) {
      if (_seen.add(n.id) && !n.read) alerts.show(n);
    }
  }
}
