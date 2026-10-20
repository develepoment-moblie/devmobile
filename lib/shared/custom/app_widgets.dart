import 'package:flutter/material.dart';

import 'app_theme.dart';

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
        child: Column(
          children: [
            Icon(icon, size: 48, color: AppColors.primary),
            EmptyState(
              'Module en construction',
              '$title · responsable : $owner',
            ),
          ],
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
