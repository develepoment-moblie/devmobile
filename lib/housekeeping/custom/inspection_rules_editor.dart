import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../services/inspection_scoring.dart';
import 'draft_guard.dart';
import 'housekeeping_widgets.dart';

// Edits a category's inspection grading: pass threshold and the weight of
// each checklist item. Used by the supervisor (housekeeping rules) and the
// Manager (catalog); [save] sends it through the caller's mutation path.
class InspectionRulesEditor extends StatefulWidget {
  final String category;
  final List<String> labels;
  final InspectionRules rules;
  final Future<void> Function(int threshold, Map<String, int> weights) save;
  const InspectionRulesEditor({
    super.key,
    required this.category,
    required this.labels,
    required this.rules,
    required this.save,
  });
  @override
  State<InspectionRulesEditor> createState() => _InspectionRulesEditorState();
}

class _InspectionRulesEditorState extends State<InspectionRulesEditor> {
  late int _threshold = widget.rules.threshold;
  late final Map<String, int> _weights = {
    for (final l in widget.labels) l: widget.rules.weightOf(l),
  };
  bool _busy = false;
  String? _error;

  bool get _dirty =>
      _threshold != widget.rules.threshold ||
      widget.labels.any((l) => _weights[l] != widget.rules.weightOf(l));

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(_threshold, Map.of(_weights));
      if (!mounted) return;
      showFeedback(context, 'Barème enregistré pour ${widget.category}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DraftGuard(
    dirty: _dirty && !_busy,
    busy: _busy,
    child: Scaffold(
      appBar: AppBar(title: Text('Barème · ${widget.category}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [
          const Text(
            'Chaque point vaut OK (100 %), partiel (50 %) ou non conforme (0 %). '
            'Le score est la moyenne pondérée ; le nettoyage est validé '
            'lorsque le score atteint le seuil.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.red),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Seuil de réussite',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '$_threshold / 100',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _threshold.toDouble(),
                    min: 50,
                    max: 100,
                    divisions: 10,
                    label: '$_threshold',
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _threshold = v.round()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Poids des points de contrôle',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final label in widget.labels)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(child: Text(label)),
                    IconButton(
                      tooltip: 'Diminuer le poids de $label',
                      onPressed: _busy || _weights[label]! <= minItemWeight
                          ? null
                          : () => setState(
                              () => _weights[label] = _weights[label]! - 1,
                            ),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${_weights[label]}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Augmenter le poids de $label',
                      onPressed: _busy || _weights[label]! >= maxItemWeight
                          ? null
                          : () => setState(
                              () => _weights[label] = _weights[label]! + 1,
                            ),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Enregistrer le barème'),
          ),
        ],
      ),
    ),
  );
}
