import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import 'draft_guard.dart';

// Asks for one text and runs [save] with it; stays open with the error if
// saving fails. Returns true once saved.
class TextPromptDialog extends StatefulWidget {
  final String title, label, action;
  final String? message, hint;
  final int maxLength;
  final bool required, destructive;
  final Future<void> Function(String text) save;
  const TextPromptDialog({
    super.key,
    required this.title,
    required this.label,
    required this.action,
    required this.save,
    this.message,
    this.hint,
    this.maxLength = 300,
    this.required = true,
    this.destructive = false,
  });
  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  final _form = GlobalKey<FormState>();
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(_text.text.trim());
      if (!mounted) return;
      _text.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DraftGuard(
    dirty: _text.text.isNotEmpty,
    busy: _busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.message != null) ...[
              Text(
                widget.message!,
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.red),
                  ),
                ),
              ),
            TextFormField(
              controller: _text,
              enabled: !_busy,
              autofocus: true,
              maxLength: widget.maxLength,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
              ),
              validator: (v) =>
                  widget.required && (v == null || v.trim().isEmpty)
                  ? 'Ce champ est obligatoire.'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.maybePop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.red)
              : null,
          onPressed: _busy ? null : _save,
          child: Text(widget.action),
        ),
      ],
    ),
  );
}
