import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/app_user.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/guest_home.dart';
import 'screens/staff_home.dart';
import 'screens/manager_home.dart';
import 'screens/maintenance_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://xgqhssfzbhmnxdrijogf.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhncWhzc2Z6Ymhtbnhkcmlqb2dmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIwNTc1OTEsImV4cCI6MjEwNzYzMzU5MX0.QdjZI0LQxKYDd488oM3v-jeQbkpYYTupgpSCVVRrRo0',
  );
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
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, _) {
        if (supabase.auth.currentSession == null) {
          return const LoginScreen();
        }

        return FutureBuilder<AppUser>(
          future: AuthService.currentProfile(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.redAccent),
                        const SizedBox(height: 16),
                        Text('Erreur: ${snap.error}',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => AuthService.logout(),
                          child: const Text('Se déconnecter'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final user = snap.data!;
            switch (user.role) {
            // 👇 admin ET manager gèrent la même chose
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
          },
        );
      },
    );
  }
}