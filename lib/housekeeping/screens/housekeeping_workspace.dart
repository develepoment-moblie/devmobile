import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/nova_icon.dart';
import '../models/hotel_data.dart';
import '../services/phone_alerts.dart';
import 'agent_dashboard_screen.dart';
import 'agent_rooms_screen.dart';
import 'details_screen.dart';
import 'qr_scan_screen.dart';
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

  /// Phone notifications for new alerts; none in tests.
  final PhoneAlerts? alerts;
  const HousekeepingWorkspace({
    super.key,
    required this.data,
    required this.agent,
    this.alerts,
  });
  @override
  State<HousekeepingWorkspace> createState() => _HousekeepingWorkspaceState();
}

class _HousekeepingWorkspaceState extends State<HousekeepingWorkspace>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  HotelData get data => widget.data;
  late final _watcher = widget.alerts == null
      ? null
      : AlertWatcher(widget.alerts!);
  void _watch() => _watcher?.check(
    widget.agent ? data.personalNotifications : data.notifications,
  );
  int destination = 0;
  final _history = <int>[];
  // Fades the newly selected tab in; the tabs themselves keep their state.
  late final _tabFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  late final _tabCurve = CurvedAnimation(
    parent: _tabFade,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    data.onChanged = () {
      _watch();
      if (mounted) setState(() {});
    };
    _watch();
    // No polling: HotelData re-reads after every saved change, including
    // other modules' events (the store's change signal).
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    data.onChanged = null;
    _tabFade.dispose();
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

  void _show(int index) {
    setState(() => destination = index);
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _tabFade.forward(from: 0);
    }
  }

  void navigate(int index) {
    if (destination == index) return;
    FocusScope.of(context).unfocus();
    _history.add(destination);
    _show(index);
  }

  void openHousekeeping() => navigate(4);

  // Scan a door code, then open the room if this person may see it.
  Future<void> scan() async {
    final number = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (number == null || !mounted) return;
    await _refresh();
    if (!mounted) return;
    final room = data.rooms.where((r) => r.number == number).firstOrNull;
    if (room == null || !(data.isSupervisor || data.canClean(room))) {
      showFeedback(
        context,
        room == null
            ? 'Chambre $number inconnue ou archivée.'
            : 'La chambre $number ne vous est pas attribuée.',
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DetailsScreen(data: data, room: room),
      ),
    );
  }

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
        _show(_history.removeLast());
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
                // Leaves the module at once; system Back still steps through tabs.
                onBack: () => Navigator.of(context).pop(),
                onScan: scan,
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
                  child: FadeTransition(
                    opacity: _tabCurve,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, .02),
                        end: Offset.zero,
                      ).animate(_tabCurve),
                      child: IndexedStack(
                        index: destination,
                        children: screens,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: NavigationBar(
            selectedIndex: destination,
            onDestinationSelected: navigate,
            destinations: [
              for (final tab in tabs)
                NavigationDestination(
                  icon: NovaIcon(tab.$2, color: AppColors.muted),
                  selectedIcon: NovaIcon(tab.$2, color: AppColors.primary),
                  label: tab.$1,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
