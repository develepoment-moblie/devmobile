import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../../shared/custom/nova_logo.dart';
import '../services/demo_accounts.dart';
import '../services/user_repository.dart';

class LoginScreen extends StatefulWidget {
  final UserRepository auth;
  const LoginScreen({super.key, required this.auth});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  DemoAccounts? get demo =>
      widget.auth is DemoAccounts ? widget.auth as DemoAccounts : null;
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  bool register = false, busy = false, obscure = true;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (register) {
        await widget.auth.register(
          email.text.trim(),
          password.text,
          name.text.trim(),
        );
      } else {
        await widget.auth.login(email.text.trim(), password.text);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = userError(e);
          if (!register) password.clear();
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: AutofillGroup(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: NovaLogo(size: 132)),
                  const SizedBox(height: 12),
                  Text(
                    register ? 'Créer un compte' : 'Bienvenue à Nova Paris',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    register
                        ? 'Créez votre compte client. Pour un compte Agent ou Gouvernante, demandez au Manager de vous ajouter.'
                        : 'Connectez-vous à votre espace.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 24),
                  if (demo != null && !register) ...[
                    const Text(
                      'Comptes de démonstration',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final entry in demo!.demoAccounts.entries)
                          ActionChip(
                            label: Text(entry.value),
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    email.text = entry.key;
                                    password.text = demo!.demoAccountPassword;
                                    error = null;
                                  }),
                          ),
                      ],
                    ),
                    const Text(
                      'Choisissez un compte puis connectez-vous. Données de test uniquement.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          error!,
                          style: const TextStyle(color: AppColors.red),
                        ),
                      ),
                    ),
                  if (register) ...[
                    TextFormField(
                      controller: name,
                      enabled: !busy,
                      autofillHints: const [AutofillHints.name],
                      textCapitalization: TextCapitalization.words,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Nom complet',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Renseignez votre nom.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: email,
                    enabled: !busy,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                    validator: (v) =>
                        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch(v?.trim() ?? '')
                        ? null
                        : 'Renseignez un e-mail valide.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: password,
                    enabled: !busy,
                    obscureText: obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: [
                      register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      helperText: register ? '6 caractères minimum' : null,
                      suffixIcon: IconButton(
                        tooltip: obscure
                            ? 'Afficher le mot de passe'
                            : 'Masquer le mot de passe',
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (v) => v == null || v.isEmpty
                        ? 'Renseignez le mot de passe.'
                        : register && v.length < 6
                        ? 'Utilisez au moins 6 caractères.'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: busy ? null : submit,
                      child: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(register ? 'Créer un compte' : 'Se connecter'),
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            register = !register;
                            error = null;
                            form.currentState?.reset();
                          }),
                    child: Text(
                      register ? 'J’ai déjà un compte' : 'Créer un compte',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
