import 'package:flutter/material.dart';

import '../../shared/services/app_session.dart';
import '../custom/app_colors.dart';
import 'my_stays_screen.dart';
import 'search_screen.dart';

// First screen of the Réservations module (Yassmine): two tabs, Réserver
// and Séjours, with the module's own colours.
class ReservationsHomeScreen extends StatefulWidget {
  final AppSession session;
  const ReservationsHomeScreen({super.key, required this.session});

  @override
  State<ReservationsHomeScreen> createState() => _ReservationsHomeScreenState();
}

class _ReservationsHomeScreenState extends State<ReservationsHomeScreen> {
  int _index = 0;
  final _pages = const [SearchScreen(), MyStaysScreen()];

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: reservationsTheme(),
      child: Scaffold(
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          indicatorColor: AppColors.gold.withValues(alpha: 0.3),
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.search), label: 'Réserver'),
            NavigationDestination(
              icon: Icon(Icons.event_note),
              label: 'Séjours',
            ),
          ],
        ),
      ),
    );
  }
}

/// The look Yassmine gave the module when it ran as its own app.
ThemeData reservationsTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.navy,
    primary: AppColors.navy,
    secondary: AppColors.gold,
  ),
  scaffoldBackgroundColor: AppColors.background,
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.background,
    foregroundColor: AppColors.navy,
    elevation: 0,
    centerTitle: true,
  ),
);
