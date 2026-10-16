import 'package:flutter/material.dart';
import '../models/priority.dart';
import '../services/database_helper.dart';
import '../utils/icon_mapper.dart';

const _cream     = Color(0xFFF6F1EA);
const _darkGreen = Color(0xFF1B3A32);
const _terra     = Color(0xFFC4704F);
const _muted     = Color(0xFF8B8378);
const _salmon    = Color(0xFFD98E76);
const _danger    = Color(0xFFE8B0A0);
const _dangerTxt = Color(0xFFB5423A);
const _success   = Color(0xFFE8F0DC);
const _successTx = Color(0xFF4A6B3E);

class ManagePrioritiesScreen extends StatefulWidget {
  const ManagePrioritiesScreen({super.key});

  @override
  State<ManagePrioritiesScreen> createState() =>
      _ManagePrioritiesScreenState();
}

class _ManagePrioritiesScreenState extends State<ManagePrioritiesScreen> {
  late Future<List<Priority>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = DatabaseHelper.instance
        .getAllPriorities()
        .then((rows) => rows.map((m) => Priority.fromMap(m)).toList());
  }

  void _reload() => setState(_load);

  // ============ AJOUTER / MODIFIER ============
  Future<void> _openForm({Priority? existing}) async {
    final result = await showModalBottomSheet<Priority>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PriorityFormSheet(existing: existing),
    );

    if (result == null) return;

    try {
      if (existing == null) {
        await DatabaseHelper.instance.insertPriority(
          icon: result.icon,
          title: result.title,
          subtitle: result.subtitle,
          colorType: result.colorType,
        );
      } else {
        await DatabaseHelper.instance.updatePriority(result);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null
              ? 'Priorité ajoutée.'
              : 'Priorité mise à jour.'),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  // ============ SUPPRIMER ============
  Future<void> _delete(Priority p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer cette priorité ?'),
        content: Text('« ${p.title} » sera définitivement supprimée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (ok != true || p.id == null) return;

    try {
      await DatabaseHelper.instance.deletePriority(p.id!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Priorité supprimée.')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Color _bg(String type) {
    switch (type) {
      case 'danger':
        return _danger;
      case 'terra':
        return const Color(0xFFF0E0D5);
      default:
        return _success;
    }
  }

  Color _fg(String type) {
    switch (type) {
      case 'danger':
        return _dangerTxt;
      case 'terra':
        return _terra;
      default:
        return _successTx;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _cream,
        elevation: 0,
        iconTheme: const IconThemeData(color: _darkGreen),
        title: const Text(
          'GESTION DES PRIORITÉS',
          style: TextStyle(color: _darkGreen, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _darkGreen,
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_alert_outlined),
        label: const Text('Ajouter'),
      ),
      body: RefreshIndicator(
        color: _darkGreen,
        onRefresh: () async {
          _reload();
          await _future;
        },
        child: FutureBuilder<List<Priority>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 100),
                  Center(child: Text('Erreur: ${snap.error}')),
                ],
              );
            }

            final items = snap.data ?? [];
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 100),
                  Center(child: Text('Aucune priorité.')),
                ],
              );
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final p = items[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Dismissible(
                    key: ValueKey(p.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: _danger,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.delete_outline,
                          color: _dangerTxt),
                    ),
                    confirmDismiss: (_) async {
                      await _delete(p);
                      return false; // we handle removal ourselves
                    },
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _openForm(existing: p),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _bg(p.colorType),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  iconFromString(p.icon),
                                  color: _fg(p.colorType),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _darkGreen,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      p.subtitle,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: _muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: _muted),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ============ FORMULAIRE ============
class _PriorityFormSheet extends StatefulWidget {
  final Priority? existing;
  const _PriorityFormSheet({this.existing});

  @override
  State<_PriorityFormSheet> createState() => _PriorityFormSheetState();
}

class _PriorityFormSheetState extends State<_PriorityFormSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _subCtrl;
  late String _icon;
  late String _color;

  static const _icons = [
    'ac_unit',
    'calendar',
    'bed',
    'warning',
    'cleaning',
    'people',
    'star',
    'wrench',
    'coffee',
    'restaurant',
    'spa',
    'event',
  ];

  static const _colors = ['success', 'terra', 'danger'];

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
    _subCtrl = TextEditingController(text: widget.existing?.subtitle ?? '');
    _icon = widget.existing?.icon ?? 'warning';
    _color = widget.existing?.colorType ?? 'danger';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subCtrl.dispose();
    super.dispose();
  }

  Color _bg(String type) {
    switch (type) {
      case 'danger':
        return _danger;
      case 'terra':
        return const Color(0xFFF0E0D5);
      default:
        return _success;
    }
  }

  Color _fg(String type) {
    switch (type) {
      case 'danger':
        return _dangerTxt;
      case 'terra':
        return _terra;
      default:
        return _successTx;
    }
  }

  void _submit() {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renseigne un titre.')),
      );
      return;
    }
    Navigator.pop(
      context,
      Priority(
        id: widget.existing?.id,
        icon: _icon,
        title: _titleCtrl.text.trim(),
        subtitle: _subCtrl.text.trim(),
        colorType: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isEdit ? 'Modifier la priorité' : 'Nouvelle priorité',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _darkGreen,
              ),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Titre',
                prefixIcon: Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _subCtrl,
              decoration: const InputDecoration(
                labelText: 'Détails (ex: Ch. 305 · Urgent)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              'ICÔNE',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
                color: _muted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _icons.map((name) {
                final selected = name == _icon;
                return InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => setState(() => _icon = name),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: selected ? _darkGreen : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? _darkGreen : Colors.black12,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      iconFromString(name),
                      color: selected ? Colors.white : _darkGreen,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            const Text(
              'COULEUR',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
                color: _muted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: _colors.map((c) {
                final selected = c == _color;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _bg(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? _darkGreen : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: Icon(
                        selected ? Icons.check : Icons.circle,
                        size: selected ? 20 : 10,
                        color: _fg(c),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),

            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _salmon,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: _submit,
                child: Text(
                  isEdit ? 'Enregistrer' : 'Créer la priorité',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}