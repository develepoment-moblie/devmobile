import 'package:flutter/material.dart';

import '../../shared/custom/app_widgets.dart';
import '../../shared/custom/nova_logo.dart';
import '../models/app_user.dart';
import '../services/password_management.dart';
import '../services/user_repository.dart';
import 'password_sheet.dart';

class UserProfileScreen extends StatefulWidget {
  final AppUser user;
  final UserRepository auth;
  const UserProfileScreen({super.key, required this.user, required this.auth});
  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool busy = false;
  String? error;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const Center(child: NovaLogo(size: 156)),
      const SizedBox(height: 20),
      StaffBanner(
        title: widget.user.fullName,
        label: widget.user.roleLabel.toUpperCase(),
      ),
      const SizedBox(height: 24),
      Text('${widget.user.points} points de fidélité'),
      const SizedBox(height: 24),
      if (error != null) Text(error!),
      if (widget.auth case final PasswordManagement passwords) ...[
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  if (await showPasswordSheet(context, passwords) &&
                      context.mounted) {
                    showFeedback(context, 'Mot de passe modifié.');
                  }
                },
          icon: const Icon(Icons.lock_reset),
          label: const Text('Changer le mot de passe'),
        ),
        const SizedBox(height: 12),
      ],
      OutlinedButton.icon(
        onPressed: busy
            ? null
            : () async {
                setState(() => busy = true);
                try {
                  await widget.auth.logout();
                } catch (e) {
                  if (mounted) setState(() => error = userError(e));
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        icon: const Icon(Icons.logout),
        label: const Text('Se déconnecter'),
      ),
    ],
  );
}
