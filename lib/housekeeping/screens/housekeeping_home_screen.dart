import 'package:flutter/material.dart';

import '../../shared/models/app_user.dart';
import '../../shared/services/app_session.dart';
import '../models/hotel_data.dart';
import '../services/housekeeping_store.dart';
import '../services/phone_alerts.dart';
import '../services/sqlite_housekeeping.dart';
import '../services/sqlite_room_catalog.dart';
import 'housekeeping_workspace.dart';
import 'manage_rooms_screen.dart';

// First screen of the module: the room catalog for the Manager, otherwise the
// cleaning workspace of the supervisor or the agent.
class HousekeepingHomeScreen extends StatelessWidget {
  final AppSession session;
  final HousekeepingStore store;
  const HousekeepingHomeScreen({
    super.key,
    required this.session,
    required this.store,
  });

  @override
  Widget build(BuildContext context) =>
      session.user?.hasAnyRole(AppRole.management) == true
      ? ManageRoomsScreen(backend: SqliteRoomCatalog(store))
      : _CleaningWorkspace(session: session, store: store);
}

class _CleaningWorkspace extends StatefulWidget {
  final AppSession session;
  final HousekeepingStore store;
  const _CleaningWorkspace({required this.session, required this.store});
  @override
  State<_CleaningWorkspace> createState() => _CleaningWorkspaceState();
}

class _CleaningWorkspaceState extends State<_CleaningWorkspace> {
  late final data = HotelData(
    api: SqliteHousekeeping(widget.store, events: widget.session.events),
  )..watchLate = true;
  bool loading = true;
  String? error;
  // One instance for the app: the plugin is initialised once.
  static final _alerts = LocalPhoneAlerts();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    data.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await data.refresh();
      // Found items nobody claimed within the delay are archived.
      await data.archiveUnclaimed();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chambres et ménage')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: load, child: const Text('Réessayer')),
              ],
            ),
          ),
        ),
      );
    }
    return HousekeepingWorkspace(
      data: data,
      agent: widget.session.user?.role == AppRole.staff,
      alerts: _alerts,
    );
  }
}
