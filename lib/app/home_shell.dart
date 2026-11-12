import 'package:flutter/material.dart';

import '../shared/custom/animations.dart';
import '../shared/custom/app_theme.dart';
import '../shared/custom/app_widgets.dart';
import '../shared/custom/nova_logo.dart';
import '../shared/models/nova_module.dart';
import '../shared/services/app_session.dart';
import 'modules.dart';

// Home screen: the modules the signed-in role can open.
class HomeShell extends StatelessWidget {
  final AppSession session;
  const HomeShell({super.key, required this.session});

  static const _days = [
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ];
  static const _months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];
  static String today([DateTime? now]) {
    final d = now ?? DateTime.now();
    return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}'
        .toUpperCase();
  }

  // Each module keeps the same tint everywhere.
  static const _tints = [
    (AppColors.accent, AppColors.orangeLight),
    (AppColors.green, AppColors.greenLight),
    (AppColors.orange, AppColors.orangeLight),
    (AppColors.goldDeep, Color(0xFFF6EEDC)),
    (AppColors.primaryLight, AppColors.grayLight),
    (AppColors.primary, AppColors.greenLight),
  ];

  @override
  Widget build(BuildContext context) {
    final user = session.user!;
    final visible = [
      for (final (i, module) in novaModules.indexed)
        if (user.hasAnyRole(module.roles)) (module, _tints[i % _tints.length]),
    ];
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: HeroHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: NovaBrand(light: true),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Mon profil',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (context) =>
                                userManagement.buildProfile(context, session),
                          ),
                        ),
                        icon: InitialsAvatar(
                          name: user.fullName,
                          color: AppColors.gold,
                          size: 38,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  FadeSlideIn(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          today(),
                          style: TextStyle(
                            color: AppColors.gold.withValues(alpha: .9),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Bonjour ${user.firstName}.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            user.roleLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Vos espaces',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          if (visible.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                'Aucun module',
                'Aucun module n’est encore disponible pour votre rôle.',
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => FadeSlideIn(
                index: i + 1,
                child: _ModuleCard(
                  module: visible[i].$1,
                  tint: visible[i].$2,
                  session: session,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final NovaModule module;
  final (Color, Color) tint;
  final AppSession session;
  const _ModuleCard({
    required this.module,
    required this.tint,
    required this.session,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
      boxShadow: AppShadows.soft,
    ),
    child: PressableScale(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (context) => module.buildHome(context, session),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: tint.$2,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(module.icon, color: tint.$1, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    module.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    module.description,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.background,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
