import 'dart:async';

import 'package:flutter/material.dart';

import 'main_screen.dart';
import 'back_navigation.dart';
import '../housekeeping/models/hotel_data.dart';
import '../housekeeping/services/housekeeping_backend.dart';
import '../housekeeping/services/room_catalog_backend.dart';
import '../housekeeping/screens/manage_rooms_screen.dart';
import '../shared/services/app_exception.dart';
import '../user_management/models/app_user.dart';
import '../user_management/services/user_repository.dart';
import '../user_management/screens/login_screen.dart';
import '../user_management/screens/guest_home.dart';
import '../user_management/screens/manager_home.dart';
import '../user_management/screens/maintenance_home.dart';
import '../user_management/screens/profile_screen.dart';

class AuthGate extends StatefulWidget {
  final UserRepository auth;
  final HousekeepingBackend Function() housekeepingFactory;
  final RoomCatalogBackend Function()? roomCatalogFactory;
  final WidgetBuilder? backupsBuilder;
  const AuthGate({
    super.key,
    required this.auth,
    required this.housekeepingFactory,
    this.roomCatalogFactory,
    this.backupsBuilder,
  });
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<void>? subscription;
  Timer? timer;
  AppUser? user;
  String? error;
  bool loading = true, fetching = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    subscription = widget.auth.sessionChanges.listen((_) => load());
    timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => load(background: true),
    );
    load();
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    subscription?.cancel();
    super.dispose();
  }

  Future<void> load({bool background = false}) async {
    if (widget.auth.sessionUserId == null) {
      generation++;
      fetching = false;
      if (mounted) {
        setState(() {
          user = null;
          error = null;
          loading = false;
        });
      }
      return;
    }
    if (background && fetching) return;
    final request = ++generation;
    fetching = true;
    if (!background && mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final profile = await widget.auth.currentProfile().timeout(
        const Duration(seconds: 15),
      );
      if (mounted && request == generation) {
        setState(() {
          user = profile;
          error = null;
          loading = false;
        });
      }
    } catch (e) {
      // Fail closed: an absent/deleted or unavailable profile never keeps a role route open.
      if (mounted && request == generation) {
        setState(() {
          if (e is AppServiceException && e.status == 403 ||
              user?.id != widget.auth.sessionUserId) {
            user = null;
          }
          error = userError(e);
          loading = false;
        });
      }
    } finally {
      if (request == generation) fetching = false;
    }
  }

  Widget home(AppUser user) => switch (user.role) {
    'admin' || 'manager' => ManagerHome(
      user: user,
      auth: widget.auth,
      roomsBuilder: widget.roomCatalogFactory == null
          ? null
          : (_) => ManageRoomsScreen(backend: widget.roomCatalogFactory!()),
      backupsBuilder: widget.backupsBuilder,
    ),
    'staff' || 'supervisor' => AuthenticatedHousekeeping(
      user: user,
      auth: widget.auth,
      backend: widget.housekeepingFactory(),
    ),
    'maintenance' => MaintenanceHome(user: user, auth: widget.auth),
    'guest' => GuestHome(user: user, auth: widget.auth),
    _ => const Scaffold(
      body: Center(child: Text('Ce rôle n’est pas pris en charge.')),
    ),
  };
  @override
  Widget build(BuildContext context) {
    if (widget.auth.sessionUserId == null) {
      return LoginScreen(auth: widget.auth);
    }
    if (loading && user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final recovery = Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error ?? 'Vérification de la session…',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: load, child: const Text('Réessayer')),
                TextButton(
                  onPressed: widget.auth.logout,
                  child: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (user == null) return recovery;
    final current = user!;
    // Disposing this session-scoped navigator also removes pushed management and
    // room-detail routes on logout, user switch or role change.
    return Stack(
      children: [
        Offstage(
          offstage: error != null || loading,
          child: SessionNavigator(
            key: ValueKey('${current.id}:${current.role}:${current.revision}'),
            enabled: error == null && !loading,
            homeBuilder: (_) => home(current),
          ),
        ),
        if (error != null) recovery,
        if (loading)
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      ],
    );
  }
}

class AuthenticatedHousekeeping extends StatefulWidget {
  final AppUser user;
  final UserRepository auth;
  final HousekeepingBackend backend;
  const AuthenticatedHousekeeping({
    super.key,
    required this.user,
    required this.auth,
    required this.backend,
  });
  @override
  State<AuthenticatedHousekeeping> createState() =>
      _AuthenticatedHousekeepingState();
}

class _AuthenticatedHousekeepingState extends State<AuthenticatedHousekeeping> {
  late final data = HotelData(api: widget.backend);
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await data.refresh();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    data.dispose();
    widget.backend.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ménage')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: load, child: const Text('Réessayer')),
                TextButton(
                  onPressed: widget.auth.logout,
                  child: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return MainScreen(
      data: data,
      agentWorkspace: widget.user.role == 'staff',
      accountScreen: UserProfileScreen(user: widget.user, auth: widget.auth),
    );
  }
}
