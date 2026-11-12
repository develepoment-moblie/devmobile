import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import 'nova_icon.dart';
import '../../shared/custom/nova_logo.dart';

class NovaHeader extends StatelessWidget {
  final VoidCallback onNotifications;
  final bool unread;

  /// Shown as a back arrow before the logo, to leave the module.
  final VoidCallback? onBack;
  const NovaHeader({
    super.key,
    required this.onNotifications,
    required this.unread,
    this.onBack,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 4, 18, 9),
    child: SizedBox(
      height: 46,
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'Retour à l’accueil',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          const Expanded(
            child: Align(alignment: Alignment.centerLeft, child: NovaBrand()),
          ),
          IconButton(
            onPressed: onNotifications,
            tooltip: 'Notifications',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
                side: const BorderSide(color: AppColors.border),
              ),
            ),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const NovaIcon(NovaSymbol.bell, color: Color(0xFF49605A)),
                if (unread)
                  Positioned(
                    right: -1,
                    top: -3,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class StaffBanner extends StatelessWidget {
  final String title;
  final String label;
  const StaffBanner({
    super.key,
    required this.title,
    this.label = 'SERVICE DU MATIN',
  });
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 96),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: AppGradients.hero,
      borderRadius: BorderRadius.circular(22),
      boxShadow: AppShadows.soft,
    ),
    foregroundDecoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.gold.withValues(alpha: .18)),
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const NovaIcon(NovaSymbol.spark, color: AppColors.gold),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppColors.gold.withValues(alpha: .95),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class NovaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final NovaSymbol? symbol;
  const NovaButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.symbol,
  });
  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label)),
        if (symbol != null) ...[
          const SizedBox(width: 10),
          NovaIcon(symbol!, color: Colors.white, size: 17),
        ],
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final String title;
  final String message;
  const EmptyState(this.title, this.message, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36),
    child: Column(
      children: [
        const NovaIcon(NovaSymbol.check, size: 30, color: AppColors.green),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
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
