import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../../shared/custom/app_widgets.dart';
import '../../shared/services/app_session.dart';

// Profile of the signed-in user. Owned by user_management.
class ProfileScreen extends StatelessWidget {
  final AppSession session;
  const ProfileScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          HeroHeader(
            padding: const EdgeInsets.fromLTRB(8, 4, 22, 32),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'Retour',
                    color: Colors.white,
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
                FadeSlideIn(
                  child: Column(
                    children: [
                      InitialsAvatar(
                        name: user?.fullName ?? '',
                        color: AppColors.gold,
                        size: 84,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        user?.fullName ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.roleLabel ?? '',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .75),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: FadeSlideIn(
              index: 1,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  session.signOut();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Se déconnecter'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
