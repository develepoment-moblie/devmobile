import 'category_management_screen.dart';
import 'package:flutter/material.dart';
import '../../shared/custom/app_widgets.dart';
import '../../shared/services/app_session.dart';
import '../models/room_service.dart';
import '../services/guest_service_store.dart';

class MenuManagementScreen extends StatefulWidget {
  final AppSession session;
  const MenuManagementScreen({super.key, required this.session});
  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  late final store = GuestServiceStore(widget.session);
  List<MenuItem> items = [];
  bool archived = false, loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await store.menu(archived: archived);
      if (mounted) {
        setState(() {
          items = rows;
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Chargement impossible.';
        });
      }
    }
  }

  Future<void> edit([MenuItem? item]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _MenuForm(store: store, item: item),
      ),
    );
    if (saved == true) await load();
  }

  Future<void> archive(MenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          archived ? 'Restaurer cet article ?' : 'Archiver cet article ?',
        ),
        content: Text(
          archived
              ? 'L’article sera de nouveau visible dans la carte.'
              : 'Il sera retiré de la carte. Les anciennes commandes seront conservées.',
        ),
        actions: [
          IconButton(
            tooltip: 'Gérer les catégories',
            icon: const Icon(Icons.category_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CategoryManagementScreen(store: store),
                ),
              );
              await load();
            },
          ),

          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Revenir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy) return;
    setState(() => busy = true);
    try {
      await store.archiveMenuItem(item.id, !archived);
      await load();
    } catch (_) {
      if (mounted) showFeedback(context, 'Modification impossible.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Gestion de la carte'),
      actions: [
        IconButton(
          tooltip: 'Actualiser',
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: busy ? null : () => edit(),
      icon: const Icon(Icons.add),
      label: const Text('Ajouter'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            children: [
              SwitchListTile(
                title: const Text('Afficher les archives'),
                value: archived,
                onChanged: busy
                    ? null
                    : (value) {
                        setState(() {
                          archived = value;
                          loading = true;
                        });
                        load();
                      },
              ),
              if (error != null)
                TextButton(onPressed: load, child: Text('$error Réessayer')),
              if (items.isEmpty && error == null)
                const EmptyState(
                  'Aucun article',
                  'Ajoutez un article à votre carte.',
                ),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.symbol} ${item.name}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${item.category} · ${euros(item.priceCents)} · ${item.minutes} min',
                          ),
                          Text(item.description),
                          if (!archived)
                            Text(
                              item.available ? 'Disponible' : 'Indisponible',
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (!archived)
                                TextButton.icon(
                                  onPressed: busy ? null : () => edit(item),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Modifier'),
                                ),
                              TextButton.icon(
                                onPressed: busy ? null : () => archive(item),
                                icon: Icon(
                                  archived
                                      ? Icons.restore
                                      : Icons.archive_outlined,
                                ),
                                label: Text(
                                  archived ? 'Restaurer' : 'Archiver',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
  );
}

class _MenuForm extends StatefulWidget {
  final GuestServiceStore store;
  final MenuItem? item;
  const _MenuForm({required this.store, this.item});
  @override
  State<_MenuForm> createState() => _MenuFormState();
}

class _MenuFormState extends State<_MenuForm> {
  List<String> categories = [];
  String? categoryError;
  @override
  void initState() {
    super.initState();
    loadCategories();
  }

  Future<void> loadCategories() async {
    try {
      final rows = await widget.store.categories();
      if (mounted) {
        setState(() {
          categories = rows.map((r) => r['name'] as String).toList();
          if (!categories.contains(category)) {
            category = categories.isEmpty ? '' : categories.first;
          }
          categoryError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => categoryError = 'Impossible de charger les catégories.');
      }
    }
  }

  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.item?.name);
  late final description = TextEditingController(
    text: widget.item?.description,
  );
  late final price = TextEditingController(
    text: widget.item == null
        ? ''
        : (widget.item!.priceCents / 100).toStringAsFixed(2),
  );
  late final minutes = TextEditingController(
    text: '${widget.item?.minutes ?? 20}',
  );
  late final allergens = TextEditingController(text: widget.item?.allergens);
  late final symbol = TextEditingController(text: widget.item?.symbol ?? '🍽️');
  late String category = widget.item?.category ?? 'Plats';
  late bool vegetarian = widget.item?.vegetarian ?? false;
  bool busy = false;
  @override
  void dispose() {
    for (final c in [name, description, price, minutes, allergens, symbol]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get cents {
    final text = price.text.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d{1,4}(\.\d{1,2})?$').hasMatch(text)) return null;
    return (double.parse(text) * 100).round();
  }

  int? get preparationMinutes {
    final value = minutes.text.trim();
    return RegExp(r'^\d{1,3}$').hasMatch(value) ? int.parse(value) : null;
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await widget.store.saveMenuItem(
        MenuItem(
          widget.item?.id ?? 'menu-${DateTime.now().microsecondsSinceEpoch}',
          name.text.trim(),
          description.text.trim(),
          category,
          symbol.text.trim(),
          cents!,
          preparationMinutes!,
          allergens.text.trim(),
          vegetarian: vegetarian,
          version: widget.item?.version ?? 1,
        ),
        create: widget.item == null,
      );
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (error) {
      if (mounted) showFeedback(context, error.message);
    } catch (_) {
      if (mounted) {
        showFeedback(
          context,
          'Enregistrement impossible. Vérifiez les champs et réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.item == null ? 'Nouvel article' : 'Modifier l’article',
      ),
    ),
    body: Form(
      key: form,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: name,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Nom'),
            validator: (v) => v!.trim().isEmpty ? 'Nom obligatoire' : null,
          ),
          TextFormField(
            controller: description,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          if (categoryError != null)
            TextButton(onPressed: loadCategories, child: Text(categoryError!)),
          DropdownButtonFormField<String>(
            key: ValueKey(categories.join()),
            initialValue: categories.contains(category) ? category : null,
            validator: (value) => value == null
                ? "Créez une catégorie active avant d’enregistrer."
                : null,
            decoration: const InputDecoration(labelText: 'Catégorie'),
            items: [
              for (final c in categories)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => category = v!,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Prix en euros'),
            validator: (_) => cents == null || cents! < 1 || cents! > 100000
                ? 'Prix entre 0,01 et 1 000 €, deux décimales maximum'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: minutes,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Préparation en minutes',
            ),
            validator: (_) {
              final duration = preparationMinutes;
              return duration == null || duration < 1 || duration > 180
                  ? 'Saisissez un nombre entier de 1 à 180 minutes.'
                  : null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: allergens,
            maxLength: 250,
            decoration: const InputDecoration(labelText: 'Allergènes'),
            validator: (v) => v!.trim().isEmpty
                ? 'Indiquez les allergènes ou les informations à confirmer'
                : null,
          ),
          TextFormField(
            controller: symbol,
            maxLength: 16,
            decoration: const InputDecoration(labelText: 'Symbole ou emoji'),
          ),
          SwitchListTile(
            title: const Text('Végétarien'),
            value: vegetarian,
            onChanged: busy ? null : (v) => setState(() => vegetarian = v),
          ),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Enregistrement…' : 'Enregistrer'),
          ),
        ],
      ),
    ),
  );
}
