import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../../shared/custom/draft_guard.dart';
import '../models/app_user.dart';
import '../services/password_management.dart';
import '../services/user_repository.dart';

// Changes the signed-in password, or lets a Manager set a temporary password
// for [user]. Returns true once the new password is saved.
class PasswordSheet extends StatefulWidget {
  final PasswordManagement passwords;
  final AppUser? user;
  const PasswordSheet({super.key, required this.passwords, this.user});
  @override
  State<PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<PasswordSheet> {
  final key = GlobalKey<FormState>();
  final current = TextEditingController(),
      next = TextEditingController(),
      confirm = TextEditingController();
  bool busy = false, obscure = true;
  String? error;
  bool get reset => widget.user != null;
  bool get dirty =>
      current.text.isNotEmpty || next.text.isNotEmpty || confirm.text.isNotEmpty;
  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !key.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (reset) {
        await widget.passwords.resetPassword(widget.user!, next.text);
      } else {
        await widget.passwords.changePassword(current.text, next.text);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    TextEditingController controller,
    String label, {
    String? helper,
    required String? Function(String?) validator,
  }) => TextFormField(
    controller: controller,
    enabled: !busy,
    obscureText: obscure,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      suffixIcon: IconButton(
        tooltip: obscure ? 'Afficher les mots de passe' : 'Masquer les mots de passe',
        onPressed: () => setState(() => obscure = !obscure),
        icon: Icon(
          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
    validator: validator,
  );

  @override
  Widget build(BuildContext context) => DraftGuard(
    dirty: dirty,
    busy: busy,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: key,
        onChanged: () => setState(() {}),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              reset ? 'Réinitialiser le mot de passe' : 'Changer le mot de passe',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              reset
                  ? 'Choisissez un mot de passe temporaire pour ${widget.user!.fullName} et communiquez-le en personne. Conseillez-lui de le changer depuis son profil.'
                  : 'Saisissez votre mot de passe actuel puis le nouveau.',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
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
            if (!reset) ...[
              field(
                current,
                'Mot de passe actuel',
                validator: (v) => v == null || v.isEmpty
                    ? 'Renseignez votre mot de passe actuel.'
                    : null,
              ),
              const SizedBox(height: 16),
            ],
            field(
              next,
              reset ? 'Mot de passe temporaire' : 'Nouveau mot de passe',
              helper: '6 caractères minimum',
              validator: (v) => v == null || v.length < 6
                  ? 'Utilisez au moins 6 caractères.'
                  : null,
            ),
            const SizedBox(height: 16),
            field(
              confirm,
              'Confirmer le mot de passe',
              validator: (v) => v != next.text
                  ? 'Les mots de passe ne correspondent pas.'
                  : null,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: busy ? null : save,
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(reset ? 'Réinitialiser' : 'Enregistrer'),
              ),
            ),
            TextButton(
              onPressed: busy ? null : () => Navigator.maybePop(context),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> showPasswordSheet(
  BuildContext context,
  PasswordManagement passwords, [
  AppUser? user,
]) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => PasswordSheet(passwords: passwords, user: user),
    ) ==
    true;
