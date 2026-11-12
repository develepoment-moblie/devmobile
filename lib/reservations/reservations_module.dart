import 'package:flutter/material.dart';
import 'custom/app_colors.dart';
import 'screens/my_stays_screen.dart';
import 'screens/search_screen.dart';

class ReservationsModule extends StatefulWidget {
  const ReservationsModule({super.key});
  @override
  State<ReservationsModule> createState() => _ReservationsModuleState();
}

class _ReservationsModuleState extends State<ReservationsModule> {
  int _index = 0;
  final _pages = const [SearchScreen(), MyStaysScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        indicatorColor: AppColors.gold.withOpacity(0.3),
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: 'Réserver'),
          NavigationDestination(icon: Icon(Icons.event_note), label: 'Séjours'),
        ],
      ),
    );
  }
}