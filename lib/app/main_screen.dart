import 'dart:async';

import 'package:flutter/material.dart';

import '../shared/custom/app_theme.dart';
import '../shared/custom/app_widgets.dart';
import '../shared/custom/nova_icon.dart';
import '../housekeeping/models/hotel_data.dart';
import '../housekeeping/screens/housekeeping_screen.dart';
import '../housekeeping/screens/rooms_screen.dart';
import '../housekeeping/screens/notifications_screen.dart';
import '../housekeeping/screens/supplies_screen.dart';
import '../demo/profile_screen.dart';
import '../housekeeping/screens/staff_screen.dart';
import '../housekeeping/screens/agent_dashboard_screen.dart';
import '../housekeeping/screens/agent_rooms_screen.dart';
import 'back_navigation.dart';

// Application navigation: composes feature screens and the injected account page.
// Feature modules remain independent of authentication and the app shell.
class MainScreen extends StatefulWidget {
  final HotelData? data;
  final Widget? accountScreen;
  final bool agentWorkspace;
  const MainScreen({
    super.key,
    this.data,
    this.accountScreen,
    this.agentWorkspace = false,
  });
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late final data = widget.data ?? HotelData();
  Timer? timer;
  int destination = 4;
  bool housekeeping = true;
  final _history = <({int destination, bool housekeeping})>[];
  VoidCallback? _detachBack;
  bool _appHandlesBack = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detachBack?.call();
    _detachBack = AppBackNavigation.registerTabs(context, _previousDestination);
    _appHandlesBack = AppBackNavigation.available(context);
  }

  @override
  void initState() {
    super.initState();
    if (widget.agentWorkspace) {
      destination = 0;
      housekeeping = false;
    }
    WidgetsBinding.instance.addObserver(this);
    data.onChanged = () {
      if (mounted) setState(() {});
    };
    if (data.isConnected) {
      timer = Timer.periodic(const Duration(seconds: 5), (_) async {
        try {
          await data.refresh();
        } catch (_) {
          /* Persistent banner below. */
        }
      });
    }
  }

  @override
  void dispose() {
    _detachBack?.call();
    WidgetsBinding.instance.removeObserver(this);
    data.onChanged = null;
    timer?.cancel();
    if (widget.data == null) data.dispose();
    super.dispose();
  }

  void _select(int index, {bool showHousekeeping = false}) {
    if (destination == index && housekeeping == showHousekeeping) return;
    AppBackNavigation.reset(context);
    FocusScope.of(context).unfocus();
    setState(() {
      _history.add((destination: destination, housekeeping: housekeeping));
      destination = index;
      housekeeping = showHousekeeping;
    });
  }

  void navigate(int index) => _select(index);
  void openHousekeeping() => _select(4, showHousekeeping: true);

  bool _previousDestination() {
    if (!mounted || _history.isEmpty) return false;
    final previous = _history.removeLast();
    setState(() {
      destination = previous.destination;
      housekeeping = previous.housekeeping;
    });
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && data.isConnected) {
      data.refresh().catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      widget.agentWorkspace
          ? AgentDashboardScreen(data: data, onRooms: () => navigate(2))
          : StaffScreen(
              data: data,
              navigate: navigate,
              onHousekeeping: openHousekeeping,
            ),
      widget.agentWorkspace
          ? const SizedBox.shrink()
          : RoomsScreen(
              key: const ValueKey('departures'),
              data: data,
              departuresOnly: true,
            ),
      widget.agentWorkspace
          ? AgentRoomsScreen(data: data)
          : RoomsScreen(key: const ValueKey('rooms'), data: data),
      widget.agentWorkspace
          ? const SizedBox.shrink()
          : SuppliesScreen(data: data),
      widget.accountScreen ??
          ProfileScreen(data: data, onHousekeeping: openHousekeeping),
    ];
    return PopScope<Object?>(
      canPop: _appHandlesBack || _history.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_appHandlesBack) _previousDestination();
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
                      onPressed: () async {
                        try {
                          await data.refresh();
                        } catch (_) {}
                      },
                      child: const Text('Actualiser'),
                    ),
                  ],
                ),
              NovaHeader(
                unread: widget.agentWorkspace
                    ? data.personalNotifications.any((n) => !n.read)
                    : data.unread > 0,
                onNotifications: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotificationsScreen(
                        data: data,
                        personalOnly: widget.agentWorkspace,
                      ),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    try {
                      await data.refresh();
                    } catch (_) {
                      /* Recovery banner. */
                    }
                  },
                  notificationPredicate: (event) =>
                      data.isConnected && event.depth == 0,
                  child: IndexedStack(
                    index: housekeeping ? 5 : destination,
                    children: [
                      ...screens,
                      widget.agentWorkspace
                          ? const SizedBox.shrink()
                          : HousekeepingScreen(data: data),
                    ],
                  ),
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
                children: List.generate(widget.agentWorkspace ? 3 : 5, (
                  position,
                ) {
                  final index = widget.agentWorkspace
                      ? [0, 2, 4][position]
                      : position;
                  const labels = [
                    'Accueil',
                    'Réservations',
                    'Chambres',
                    'Services',
                    'Profil',
                  ];
                  const icons = [
                    NovaSymbol.home,
                    NovaSymbol.calendar,
                    NovaSymbol.bed,
                    NovaSymbol.service,
                    NovaSymbol.person,
                  ];
                  final selected = destination == index;
                  final color = selected
                      ? AppColors.primary
                      : const Color(0xFF929B98);
                  return Expanded(
                    child: Semantics(
                      selected: selected,
                      child: TextButton(
                        onPressed: () => navigate(index),
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
                            NovaIcon(icons[index], color: color),
                            const SizedBox(height: 5),
                            Text(
                              widget.agentWorkspace
                                  ? [
                                      'Mon service',
                                      'Mes chambres',
                                      'Profil',
                                    ][position]
                                  : labels[index],
                              textAlign: widget.agentWorkspace
                                  ? TextAlign.center
                                  : null,
                              style: TextStyle(
                                fontSize: widget.agentWorkspace ? 11 : 6.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
