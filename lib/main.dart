import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/app_user.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/guest_home.dart';
import 'screens/staff_home.dart';
import 'screens/manager_home.dart';
import 'screens/maintenance_home.dart';
import 'screens/reset_password_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://xgqhssfzbhmnxdrijogf.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhncWhzc2Z6Ymhtbnhkcmlqb2dmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIwNTc1OTEsImV4cCI6MjEwNzYzMzU5MX0.QdjZI0LQxKYDd488oM3v-jeQbkpYYTupgpSCVVRrRo0',
    // 👇 FORCE Implicit Flow — plus de code_verifier à chercher
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
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

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _showResetPassword = false;
  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();

    // 🔍 Traite immédiatement l'URL de recovery au démarrage
    _handleRecoveryUrl();

    // 🎧 Écoute les événements d'auth
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        if (mounted) {
          setState(() => _showResetPassword = true);
        }
      }
    });
  }

  /// Détecte et traite le lien de réinitialisation
  Future<void> _handleRecoveryUrl() async {
    final uri = Uri.base;

    // 1️⃣ Implicit Flow : #access_token=xxx&type=recovery
    if (uri.fragment.contains('type=recovery') ||
        uri.fragment.contains('access_token=')) {
      if (mounted) {
        setState(() => _showResetPassword = true);
      }
      return;
    }

    // 2️⃣ PKCE Flow : ?code=xxx (fallback si Implicit désactivé)
    final code = uri.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      try {
        await supabase.auth.exchangeCodeForSession(code);
        if (mounted) {
          setState(() => _showResetPassword = true);
        }
      } catch (e) {
        debugPrint('Exchange code failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 Affiche l'écran de reset si on vient d'un lien de recovery
    if (_showResetPassword) {
      return const ResetPasswordScreen();
    }

    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Sécurité supplémentaire
        if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
          return const ResetPasswordScreen();
        }

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