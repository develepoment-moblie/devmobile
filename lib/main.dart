import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'shared/custom/app_theme.dart';
import 'app/main_screen.dart';
import 'demo/offline_store.dart';
import 'demo/connected_screen.dart';
import 'housekeeping/models/hotel_data.dart';

import 'app/auth_gate.dart';
import 'app/back_navigation.dart';
import 'app/backup_screen.dart';
import 'app/backup_service.dart';
import 'user_management/services/sqlite_user_repository.dart';
import 'housekeeping/services/sqlite_housekeeping.dart';
import 'housekeeping/services/sqlite_room_catalog.dart';
import 'user_management/services/user_repository.dart';
import 'housekeeping/services/housekeeping_backend.dart';

import 'housekeeping/services/room_catalog_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('HOUSEKEEPING_DEMO') ||
      const String.fromEnvironment('HOUSEKEEPING_API_URL').isNotEmpty) {
    runApp(const NovaParisApp());
    return;
  }
  try {
    if (const bool.fromEnvironment('LOCAL_JSON_DEMO')) {
      final store = await OfflineStore.open();
      runApp(
        NovaParisApp(
          auth: store,
          housekeepingFactory: store.housekeeping,
          roomCatalogFactory: store.roomCatalog,
          offline: true,
        ),
      );
      return;
    }
    final store = await SqliteUserRepository.open();
    final backups = LocalBackupService(store);
    runApp(
      NovaParisApp(
        auth: store,
        housekeepingFactory: () => SqliteHousekeeping(store),
        roomCatalogFactory: () => SqliteRoomCatalog(store),
        backupsBuilder: (_) => BackupScreen(service: backups),
        local: true,
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        theme: novaTheme(),
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Les données n’ont pas pu être ouvertes. Vérifiez l’espace disponible puis relancez l’application. Consultez SQLITE.md dans le projet si le problème persiste.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NovaParisApp extends StatelessWidget {
  final HotelData? data;
  final bool offline;
  final bool local;
  final UserRepository? auth;
  final HousekeepingBackend Function()? housekeepingFactory;
  final RoomCatalogBackend Function()? roomCatalogFactory;
  final WidgetBuilder? backupsBuilder;
  const NovaParisApp({
    super.key,
    this.data,
    this.offline = false,
    this.local = false,
    this.auth,
    this.housekeepingFactory,
    this.roomCatalogFactory,
    this.backupsBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final navigationObserver = AppNavigationObserver();
    return MaterialApp(
      navigatorObservers: [navigationObserver],
      title: 'Nova Paris',
      debugShowCheckedModeBanner: false,
      theme: novaTheme(),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => ColoredBox(
        color: AppColors.tabs,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 402),
            child: offline || local
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Material(
                        color: AppColors.primary,
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Text(
                              local ? 'Mode local · données sur cet appareil' : 'Démo hors ligne · données sur cet appareil',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: child!),
                    ],
                  )
                : child!,
          ),
        ),
      ),
      home: AppBackNavigation(
        observer: navigationObserver,
        child: auth != null
            ? AuthGate(
                auth: auth!,
                housekeepingFactory: housekeepingFactory!,
                roomCatalogFactory: roomCatalogFactory,
                backupsBuilder: backupsBuilder,
              )
            : data != null
            ? MainScreen(data: data)
            : (const String.fromEnvironment('HOUSEKEEPING_API_URL')
                      .isNotEmpty ||
                  const String.fromEnvironment('HOUSEKEEPING_TOKEN').isNotEmpty)
            ? const ConnectedScreen(
                url: String.fromEnvironment('HOUSEKEEPING_API_URL'),
                token: String.fromEnvironment('HOUSEKEEPING_TOKEN'),
              )
            : const MainScreen(),
      ),
    );
  }
}
