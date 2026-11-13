import 'package:flutter/material.dart';

import '../../shared/services/app_session.dart';
import '../custom/app_colors.dart';
import 'my_stays_screen.dart';
import 'search_screen.dart';

class ReservationsHomeScreen extends StatefulWidget {
  final AppSession session;
  const ReservationsHomeScreen({super.key, required this.session});

  @override
  State<ReservationsHomeScreen> createState() => _ReservationsHomeScreenState();
}

class _ReservationsHomeScreenState extends State<ReservationsHomeScreen> {
  int index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: index,
      children: const [SearchScreen(), MyStaysScreen()],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      indicatorColor: AppColors.gold.withValues(alpha: 0.3),
      onDestinationSelected: (value) => setState(() => index = value),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.search), label: 'Réserver'),
        NavigationDestination(icon: Icon(Icons.event_note), label: 'Séjours'),
      ],
    ),
  );
}
