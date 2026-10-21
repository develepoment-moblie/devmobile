import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../custom/busy_action.dart';
import '../models/hotel_data.dart';
import '../services/notification_rules.dart';

// Each user's notification switches, one per category. A category switched
// off is neither listed nor shown on the phone.
class NotificationPrefsScreen extends StatefulWidget {
  final HotelData data;
  const NotificationPrefsScreen({super.key, required this.data});
  @override
  State<NotificationPrefsScreen> createState() =>
      _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen>
    with ListenTo, BusyAction {
  @override
  Listenable get listenable => widget.data;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages des notifications')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [
          const Text(
            'Choisissez ce que vous recevez, dans l’application et sur le téléphone. Ces réglages ne concernent que vous.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
            ),
          const SizedBox(height: 8),
          for (final category in data.notificationCategories)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(notificationCategoryLabels[category]!),
              value: data.notifies(category),
              onChanged: busy
                  ? null
                  : (on) => run(
                      () => data.setNotificationPref(category, on),
                      on
                          ? 'Notifications activées'
                          : 'Notifications désactivées',
                    ),
            ),
          const SizedBox(height: 16),
          const Text(
            'Les notifications du téléphone s’affichent tant que l’application est ouverte ou en arrière-plan. Autorisez-les dans les réglages d’Android si rien ne s’affiche.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
