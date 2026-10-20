import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../../shared/custom/nova_logo.dart';
import '../../shared/models/app_user.dart';
import '../../shared/services/app_session.dart';

// TEMPORARY test login: pick a name and a role, no password.
// It lets every teammate open their module with the right role.
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
  final name = TextEditingController();
  String role = AppRole.manager;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void submit() {
    if (!form.currentState!.validate()) return;
    widget.session.signIn(
      AppUser(id: 'test-$role', fullName: name.text.trim(), role: role),
    );
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
                  'Connexion de test : choisissez un rôle pour ouvrir les modules correspondants.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nom'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Renseignez un nom.'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Rôle'),
                  items: [
                    for (final entry in AppRole.labels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) => setState(() => role = value!),
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
