import 'package:flutter/material.dart';

Future<bool> confirmDiscard(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Abandonner les modifications ?'),
        content: const Text('Vos modifications ne sont pas enregistrées.'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer la saisie'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    ) ??
    false;

// Shared by task and profile forms. Drafts stay in memory, never in storage.
class DraftGuard extends StatefulWidget {
  final bool dirty, busy;
  final Widget child;
  const DraftGuard({
    super.key,
    required this.dirty,
    required this.busy,
    required this.child,
  });
  @override
  State<DraftGuard> createState() => _DraftGuardState();
}

class _DraftGuardState extends State<DraftGuard> {
  bool confirming = false, allowPop = false;
  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: allowPop || (!widget.dirty && !widget.busy),
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || widget.busy || confirming) return;
      confirming = true;
      final discard = await confirmDiscard(context);
      confirming = false;
      if (!mounted || !discard || widget.busy) return;
      setState(() => allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(result);
      });
    },
    child: widget.child,
  );
}
