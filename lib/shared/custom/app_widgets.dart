import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_user.dart';
import 'animations.dart';
import 'app_theme.dart';

/// One colour per role, for avatars and labels.
Color roleColor(String role) => switch (role) {
  AppRole.manager || AppRole.admin => AppColors.primary,
  AppRole.supervisor => AppColors.goldDeep,
  AppRole.staff => AppColors.green,
  AppRole.receptionist => AppColors.accent,
  AppRole.maintenance => AppColors.orange,
  _ => AppColors.gray,
};

class EmptyState extends StatelessWidget {
  final String title;
  final String message;
  const EmptyState(this.title, this.message, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
    child: Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}

/// Dark green header with soft gold rings, used at the top of main screens.
class HeroHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const HeroHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 12, 22, 28),
  });
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
    ),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: AppGradients.hero,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: AppShadows.lifted,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        child: Stack(
          children: [
            const Positioned(right: -60, top: -40, child: _Ring(size: 220)),
            const Positioned(right: 40, bottom: -70, child: _Ring(size: 140)),
            SafeArea(
              bottom: false,
              child: Padding(padding: padding, child: child),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Ring extends StatelessWidget {
  final double size;
  const _Ring({required this.size});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.gold.withValues(alpha: .16),
          width: 1.4,
        ),
      ),
    ),
  );
}

/// Round initials avatar, tinted by a seed (for example a role).
class InitialsAvatar extends StatelessWidget {
  final String name;
  final Color color;
  final double size;
  const InitialsAvatar({
    super.key,
    required this.name,
    required this.color,
    this.size = 44,
  });
  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts
        .take(2)
        .map((p) => p.isEmpty ? '' : p.characters.first.toUpperCase())
        .join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: size * .36,
        ),
      ),
    );
  }
}

// Temporary first screen of a module that has not been built yet.
class ModulePlaceholder extends StatelessWidget {
  final String title;
  final String owner;
  final IconData icon;
  const ModulePlaceholder({
    super.key,
    required this.title,
    required this.owner,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: FadeSlideIn(
          child: Column(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  gradient: AppGradients.hero,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.lifted,
                ),
                child: Icon(icon, size: 44, color: AppColors.gold),
              ),
              EmptyState(
                'Module en construction',
                '$title · responsable : $owner',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void showFeedback(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
}
