import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/hotel_data.dart';

/// Shows housekeeping notifications as phone notifications (Android).
/// Only notifications that arrive while the app runs are shown; the ones
/// already there when the workspace opens are not repeated.
abstract interface class PhoneAlerts {
  /// Sets up the channel and asks Android for permission once.
  Future<void> prepare();
  Future<void> show(HotelNotification notification);
}

class LocalPhoneAlerts implements PhoneAlerts {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;
  int _next = 0;

  Future<bool> _init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
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
        id: _next++,
        title: n.title,
        body: n.message,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'housekeeping',
            'Ménage',
            channelDescription:
                'Attributions, validations, stock et objets trouvés.',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (error) {
      debugPrint('housekeeping: notification non affichée ($error)');
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
