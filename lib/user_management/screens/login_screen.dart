import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../../shared/custom/app_widgets.dart';
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
    body: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: HeroHeader(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: FadeSlideIn(
              offset: const Offset(0, -12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: double.infinity),
                  const NovaLogo(size: 116, light: true),
                  const SizedBox(height: 8),
                  Text(
                    'Bienvenue',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'L’hôtel, toutes équipes réunies.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          sliver: SliverToBoxAdapter(
            child: Form(
              key: form,
              child: FormField<AppUser>(
                validator: (_) =>
                    person == null ? 'Choisissez une personne.' : null,
                builder: (field) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Qui êtes-vous ?',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Connexion de test : choisissez une personne pour ouvrir les modules de son rôle.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) => Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final (i, user)
                              in DemoStaffDirectory.people.indexed)
                            SizedBox(
                              width: (constraints.maxWidth - 10) / 2,
                              child: FadeSlideIn(
                                index: i,
                                child: _PersonTile(
                                  user: user,
                                  selected: person == user,
                                  onTap: () {
                                    setState(() => person = user);
                                    field.didChange(user);
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: field.hasError
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                field.errorText!,
                                style: const TextStyle(color: AppColors.red),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: submit,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      iconAlignment: IconAlignment.end,
                      label: Text(
                        person == null
                            ? 'Entrer (mode test)'
                            : 'Entrer · ${person!.firstName}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _PersonTile extends StatelessWidget {
  final AppUser user;
  final bool selected;
  final VoidCallback onTap;
  const _PersonTile({
    required this.user,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = roleColor(user.role);
    return Semantics(
      selected: selected,
      button: true,
      label: '${user.fullName} · ${user.roleLabel}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? AppColors.greenLight : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected ? AppShadows.soft : const [],
        ),
        child: PressableScale(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InitialsAvatar(name: user.fullName, color: color, size: 40),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: selected
                          ? const Icon(
                              Icons.check_circle_rounded,
                              key: ValueKey('on'),
                              color: AppColors.primary,
                            )
                          : const Icon(
                              Icons.circle_outlined,
                              key: ValueKey('off'),
                              color: AppColors.border,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  user.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.roleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
