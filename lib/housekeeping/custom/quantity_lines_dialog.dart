import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/custom/app_theme.dart';
import 'draft_guard.dart';

/// One line of [QuantityLinesDialog].
class QuantityLine {
  final String key, label;
  final String? detail;
  final int initial, max;
  const QuantityLine(
    this.key,
    this.label, {
    this.detail,
    this.initial = 0,
    this.max = 1000,
  });
}

// A quantity per item (laundry, requests, restock, usage, minibar), with an
// optional note. Runs [save] with the quantities above zero (or all of them
// when [keepZero]); stays open with the error if saving fails. Returns true
// once saved.
class QuantityLinesDialog extends StatefulWidget {
  final String title, action;
  final String? message, noteLabel;
  final List<QuantityLine> lines;
  final bool keepZero;
  final Future<void> Function(Map<String, int> quantities, String note) save;
  const QuantityLinesDialog({
    super.key,
    required this.title,
    required this.action,
    required this.lines,
    required this.save,
    this.message,
    this.noteLabel,
    this.keepZero = false,
  });
  @override
  State<QuantityLinesDialog> createState() => _QuantityLinesDialogState();
}

class _QuantityLinesDialogState extends State<QuantityLinesDialog> {
  final _form = GlobalKey<FormState>();
  late final _fields = {
    for (final l in widget.lines)
      l.key: TextEditingController(text: l.initial == 0 ? '' : '${l.initial}'),
  };
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  int _value(String key) => int.tryParse(_fields[key]!.text.trim()) ?? 0;

  bool get _dirty =>
      _note.text.isNotEmpty ||
      widget.lines.any((l) => _value(l.key) != l.initial);

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final quantities = {
      for (final l in widget.lines)
        if (widget.keepZero || _value(l.key) > 0) l.key: _value(l.key),
    };
    if (!widget.keepZero && quantities.isEmpty) {
      setState(() => _error = 'Indiquez au moins une quantité.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(quantities, _note.text.trim());
      if (!mounted) return;
      for (final c in _fields.values) {
        c.clear();
      }
      _note.clear();
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
    dirty: _dirty,
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
              const SizedBox(height: 8),
            ],
            if (widget.lines.isEmpty) const Text('Aucun article disponible.'),
            for (final line in widget.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.label,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (line.detail != null)
                            Text(
                              line.detail!,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 78,
                      child: TextFormField(
                        key: ValueKey('qty-${line.key}'),
                        controller: _fields[line.key],
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          hintText: '0',
                          isDense: true,
                          labelText: 'Qté',
                          semanticCounterText: line.label,
                        ),
                        validator: (v) =>
                            (int.tryParse(v?.trim() ?? '') ?? 0) > line.max
                            ? '≤ ${line.max}'
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.noteLabel != null) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _note,
                enabled: !_busy,
                maxLength: 200,
                maxLines: 2,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: widget.noteLabel),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.red),
                  ),
                ),
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
          onPressed: _busy || widget.lines.isEmpty ? null : _save,
          child: Text(widget.action),
        ),
      ],
    ),
  );
}
