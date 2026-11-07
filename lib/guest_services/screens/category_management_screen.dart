import 'package:flutter/material.dart';
import '../../shared/custom/app_widgets.dart';
import '../services/guest_service_store.dart';
import 'service_desk_screen.dart' show serviceText, serviceConfirm;

class CategoryManagementScreen extends StatefulWidget {
  final GuestServiceStore store;
  const CategoryManagementScreen({super.key, required this.store});
  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  List<Map<String, Object?>> rows = [];
  bool archived = false, busy = false, loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await widget.store.categories(archived: archived);
      if (mounted) {
        setState(() {
          rows = data;
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Chargement impossible.';
          loading = false;
        });
      }
    }
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      await load();
    } on StateError catch (e) {
      if (mounted) showFeedback(context, e.message);
    } catch (_) {
      if (mounted) {
        showFeedback(context, 'Action impossible. Le nom doit être unique.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([String? previous]) async {
    final name = await serviceText(
      context,
      previous == null ? 'Nouvelle catégorie' : 'Renommer la catégorie',
      initial: previous ?? '',
      max: 60,
    );
    if (name != null && mounted) {
      await perform(() => widget.store.saveCategory(name, previous: previous));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Catégories de la carte')),
    floatingActionButton: FloatingActionButton(
      onPressed: busy ? null : () => edit(),
      tooltip: 'Ajouter une catégorie',
      child: const Icon(Icons.add),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 90),
            children: [
              SwitchListTile(
                title: const Text('Afficher les archives'),
                value: archived,
                onChanged: busy
                    ? null
                    : (v) {
                        setState(() {
                          archived = v;
                          loading = true;
                        });
                        load();
                      },
              ),
              if (error != null)
                TextButton(onPressed: load, child: Text('$error Réessayer')),
              if (rows.isEmpty && error == null)
                const EmptyState(
                  'Aucune catégorie',
                  'Ajoutez une catégorie pour organiser votre carte.',
                ),
              for (final row in rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['name']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Wrap(
                          children: [
                            if (!archived)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => edit(row['name'] as String),
                                child: const Text('Renommer'),
                              ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      if (await serviceConfirm(
                                        context,
                                        'Catégorie',
                                        archived
                                            ? 'Restaurer cette catégorie ?'
                                            : 'Archiver cette catégorie ?',
                                      )) {
                                        await perform(
                                          () => widget.store.archiveCategory(
                                            row['name'] as String,
                                            !archived,
                                          ),
                                        );
                                      }
                                    },
                              child: Text(archived ? 'Restaurer' : 'Archiver'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}
