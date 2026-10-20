import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../../shared/custom/nova_logo.dart';
import '../../shared/models/app_user.dart';
import '../../shared/services/app_session.dart';
import '../services/demo_staff_directory.dart';

// TEMPORARY test login: pick a fictional person, no password.
// It lets every teammate open their module with the right role and identity.
// The user_management owner replaces this screen with the real login
// (accounts, hashed passwords), keeping the same call: session.signIn(user).
class LoginScreen extends StatefulWidget {
  final AppSession session;
  const LoginScreen({super.key, required this.session});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  AppUser? person;

  void submit() {
    if (!form.currentState!.validate()) return;
    widget.session.signIn(person!);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: NovaLogo(size: 132)),
                const SizedBox(height: 12),
                const Text(
                  'Bienvenue à Nova Paris',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Connexion de test : choisissez une personne pour ouvrir les modules de son rôle.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<AppUser>(
                  initialValue: person,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Personne'),
                  items: [
                    for (final user in DemoStaffDirectory.people)
                      DropdownMenuItem(
                        value: user,
                        child: Text('${user.fullName} · ${user.roleLabel}'),
                      ),
                  ],
                  onChanged: (value) => setState(() => person = value),
                  validator: (value) =>
                      value == null ? 'Choisissez une personne.' : null,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: submit,
                    child: const Text('Entrer (mode test)'),
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
