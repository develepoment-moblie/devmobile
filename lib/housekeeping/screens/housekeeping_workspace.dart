import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/nova_icon.dart';
import '../models/hotel_data.dart';
import 'agent_dashboard_screen.dart';
import 'agent_rooms_screen.dart';
import 'housekeeping_screen.dart';
import 'notifications_screen.dart';
import 'rooms_screen.dart';
import 'staff_screen.dart';
import 'supplies_screen.dart';

// The module's tabs, adapted from the original app navigation:
// agents get "Mon service" and "Mes chambres"; the supervisor gets the
// home, departures, rooms, stock and cleaning review tabs. Back returns to
// the previous tab, then leaves the module.
class HousekeepingWorkspace extends StatefulWidget {
  final HotelData data;
  final bool agent;
  const HousekeepingWorkspace({
    super.key,
    required this.data,
    required this.agent,
  });
  @override
  State<HousekeepingWorkspace> createState() => _HousekeepingWorkspaceState();
}

class _HousekeepingWorkspaceState extends State<HousekeepingWorkspace>
    with WidgetsBindingObserver {
  HotelData get data => widget.data;
  Timer? timer;
  int destination = 0;
  final _history = <int>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    data.onChanged = () {
      if (mounted) setState(() {});
    };
    // Picks up changes made by other modules' events.
    timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    data.onChanged = null;
    timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await data.refresh();
    } catch (_) {
      /* The banner below shows the error. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void navigate(int index) {
    if (destination == index) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _history.add(destination);
      destination = index;
    });
  }

  void openHousekeeping() => navigate(4);

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final screens = agent
        ? [
            AgentDashboardScreen(data: data, onRooms: () => navigate(1)),
            AgentRoomsScreen(data: data),
          ]
        : [
            StaffScreen(
              data: data,
              navigate: navigate,
              onHousekeeping: openHousekeeping,
            ),
            RoomsScreen(
              key: const ValueKey('departures'),
              data: data,
              departuresOnly: true,
            ),
            RoomsScreen(key: const ValueKey('rooms'), data: data),
            SuppliesScreen(data: data),
            HousekeepingScreen(data: data),
          ];
    final tabs = agent
        ? const [
            ('Mon service', NovaSymbol.home),
            ('Mes chambres', NovaSymbol.bed),
          ]
        : const [
            ('Accueil', NovaSymbol.home),
            ('Départs', NovaSymbol.calendar),
            ('Chambres', NovaSymbol.bed),
            ('Stock', NovaSymbol.box),
            ('Ménage', NovaSymbol.spark),
          ];
    return PopScope<Object?>(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => destination = _history.removeLast());
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (data.connectionError != null)
                MaterialBanner(
                  content: Text(
                    data.connectionError!,
                    style: const TextStyle(fontSize: 12),
                  ),
                  actions: [
                    TextButton(
                      onPressed: _refresh,
                      child: const Text('Actualiser'),
                    ),
                  ],
                ),
              NovaHeader(
                onBack: () => Navigator.maybePop(context),
                unread: agent
                    ? data.personalNotifications.any((n) => !n.read)
                    : data.unread > 0,
                onNotifications: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          NotificationsScreen(data: data, personalOnly: agent),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  notificationPredicate: (event) => event.depth == 0,
                  child: IndexedStack(index: destination, children: screens),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 10, 8),
              child: Row(
                children: [
                  for (var index = 0; index < tabs.length; index++)
                    Expanded(
                      child: _TabButton(
                        label: tabs[index].$1,
                        symbol: tabs[index].$2,
                        selected: destination == index,
                        onPressed: () => navigate(index),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final NovaSymbol symbol;
  final bool selected;
  final VoidCallback onPressed;
  const _TabButton({
    required this.label,
    required this.symbol,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : const Color(0xFF929B98);
    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(vertical: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NovaIcon(symbol, color: color),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
