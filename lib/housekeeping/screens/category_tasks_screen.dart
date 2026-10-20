import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/draft_guard.dart';
import '../custom/housekeeping_widgets.dart';
import '../models/catalog_data.dart';
import '../models/task_schema.dart';
import '../services/room_catalog_backend.dart';

// The default task list of each room category.
class CategoryTasksScreen extends StatefulWidget {
  final CatalogData catalog;
  const CategoryTasksScreen({super.key, required this.catalog});
  @override
  State<CategoryTasksScreen> createState() => _CategoryTasksScreenState();
}

class _CategoryTasksScreenState extends State<CategoryTasksScreen> {
  @override
  void initState() {
    super.initState();
    widget.catalog.addListener(_changed);
  }

  @override
  void dispose() {
    widget.catalog.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.catalog.snapshot;
    final categories = snapshot?.categories ?? const <String>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Tâches par catégorie')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [
          const Text(
            'Chaque nouvelle chambre reçoit la liste de sa catégorie. Les chambres '
            'qui ne sont pas en cours de nettoyage la reçoivent aussi dès l’enregistrement.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          if (categories.isEmpty)
            const EmptyState(
              'Aucune catégorie',
              'Créez des chambres : leurs catégories apparaîtront ici.',
            ),
          for (final (i, category) in categories.indexed)
            FadeSlideIn(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    title: Text(
                      category,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      snapshot!.categoryTasks[category] == null
                          ? '${TaskSchema.labels.length} tâches standard'
                          : '${snapshot.categoryTasks[category]!.labels.length} tâches personnalisées',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => CategoryTasksEditor(
                          catalog: widget.catalog,
                          category: category,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CategoryTasksEditor extends StatefulWidget {
  final CatalogData catalog;
  final String category;
  const CategoryTasksEditor({
    super.key,
    required this.catalog,
    required this.category,
  });
  @override
  State<CategoryTasksEditor> createState() => _CategoryTasksEditorState();
}

class _CategoryTasksEditorState extends State<CategoryTasksEditor> {
  late final CategoryTasks? _saved =
      widget.catalog.snapshot?.categoryTasks[widget.category];
  late final List<String> _labels = [...(_saved?.labels ?? TaskSchema.labels)];
  late final List<String> _initial = [..._labels];
  final _input = TextEditingController();
  late final _savedEstimate =
      widget.catalog.snapshot?.estimates[widget.category];
  late final _estimate = TextEditingController(
    text: _savedEstimate == null ? '' : '${_savedEstimate.minutes}',
  );
  bool _busy = false;
  String? _error;
  bool get _dirty =>
      _input.text.isNotEmpty ||
      _labels.join('\n') != _initial.join('\n') ||
      _estimate.text.trim() != '${_savedEstimate?.minutes ?? ''}';

  @override
  void dispose() {
    _input.dispose();
    _estimate.dispose();
    super.dispose();
  }

  void _add() {
    final label = _input.text.trim();
    if (label.isEmpty) return;
    if (_labels.any((l) => l.toLowerCase() == label.toLowerCase())) {
      setState(() => _error = 'Cette tâche est déjà dans la liste.');
      return;
    }
    if (_labels.length >= 40) {
      setState(() => _error = '40 tâches au maximum.');
      return;
    }
    setState(() {
      _labels.add(label);
      _input.clear();
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_labels.isEmpty) {
      setState(() => _error = 'Gardez au moins une tâche.');
      return;
    }
    final estimate = _estimate.text.trim();
    final minutes = int.tryParse(estimate);
    if (estimate.isNotEmpty &&
        (minutes == null || minutes < 5 || minutes > 480)) {
      setState(() => _error = 'Temps estimé : de 5 à 480 minutes.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (minutes != null && minutes != _savedEstimate?.minutes) {
        await widget.catalog.change(RoomCatalogAction.setCategoryEstimate, {
          'category': widget.category,
          'minutes': minutes,
          'version': ?_savedEstimate?.version,
        });
      }
      await widget.catalog.change(RoomCatalogAction.setCategoryTasks, {
        'category': widget.category,
        'labels': _labels,
        'version': ?_saved?.version,
      });
      if (!mounted) return;
      _initial
        ..clear()
        ..addAll(_labels);
      _input.clear();
      showFeedback(context, 'Liste enregistrée pour ${widget.category}');
      Navigator.pop(context);
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
    child: Scaffold(
      appBar: AppBar(title: Text(widget.category)),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.red),
              ),
            ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              itemCount: _labels.length,
              onReorderItem: (from, to) =>
                  setState(() => _labels.insert(to, _labels.removeAt(from))),
              itemBuilder: (context, i) => Card(
                key: ValueKey(_labels[i]),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.greenLight,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(_labels[i]),
                  trailing: IconButton(
                    tooltip: 'Retirer ${_labels[i]}',
                    onPressed: _busy
                        ? null
                        : () => setState(() => _labels.removeAt(i)),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          enabled: !_busy,
                          maxLength: 120,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _add(),
                          decoration: const InputDecoration(
                            labelText: 'Nouvelle tâche',
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Ajouter la tâche',
                        onPressed: _busy ? null : _add,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _estimate,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Temps estimé de nettoyage (minutes)',
                      helperText: 'Utilisé par l’attribution automatique (30 min par défaut).',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _save,
                      child: const Text('Enregistrer la liste'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
