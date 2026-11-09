import 'package:flutter/material.dart';

import 'housekeeping_widgets.dart';

/// Runs one save at a time from a screen: [busy] disables the buttons, the
/// error stays on screen, a confirmation is shown once saved.
mixin BusyAction<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? error;

  Future<void> run(Future<void> Function() action, String done) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) showFeedback(context, done);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Shows a dialog that saves by itself and returns true once saved.
  Future<void> openDialog(Widget dialog, String done) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => dialog,
    );
    if (mounted && saved == true) showFeedback(context, done);
  }

  Future<bool> confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;
}

/// Rebuilds a screen when [listenable] changes.
mixin ListenTo<T extends StatefulWidget> on State<T> {
  Listenable get listenable;
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    listenable.addListener(_changed);
  }

  @override
  void dispose() {
    listenable.removeListener(_changed);
    super.dispose();
  }
}

String shortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
