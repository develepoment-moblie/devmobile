import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/guest_home.dart';
import 'screens/staff_home.dart';
import 'screens/manager_home.dart';
import 'screens/maintenance_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const NovaApp());
}

class NovaApp extends StatelessWidget {
  const NovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nova Paris',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF6F1EA),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B3A32)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;

    if (user == null) {
      return const LoginScreen();
    }

    switch (user.role) {
      case 'admin':
      case 'manager':
        return ManagerHome(user: user);
      case 'staff':
        return StaffHome(user: user);
      case 'maintenance':
        return MaintenanceHome(user: user);
      default:
        return GuestHome(user: user);
    }
  }
}