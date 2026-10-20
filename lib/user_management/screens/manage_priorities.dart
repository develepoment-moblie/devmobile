import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../../shared/custom/app_widgets.dart';
import '../../shared/custom/draft_guard.dart';
import '../models/priority.dart';
import '../services/priority_board.dart';
import '../services/user_repository.dart';

// Adapted from the Gestion User branch (Skander256): the Manager's priorities.
IconData priorityIcon(String name) => switch (name) {
  'ac_unit' => Icons.ac_unit,
  'calendar' => Icons.calendar_today_outlined,
  'bed' => Icons.king_bed_outlined,
  'warning' => Icons.warning_amber_rounded,
  'cleaning' => Icons.cleaning_services_outlined,
  'people' => Icons.people_outline,
  'star' => Icons.star_outline,
  'wrench' => Icons.build_outlined,
  'coffee' => Icons.coffee_outlined,
  'restaurant' => Icons.restaurant_outlined,
  'spa' => Icons.spa_outlined,
  'event' => Icons.celebration_outlined,
  _ => Icons.info_outline,
};

(Color, Color) priorityColors(String type) => switch (type) {
  'danger' => (AppColors.redLight, AppColors.red),
  'terra' => (AppColors.orangeLight, AppColors.accent),
  _ => (AppColors.greenLight, AppColors.green),
};

const priorityColorLabels = {
  'danger': 'Urgent',
  'terra': 'À suivre',
  'success': 'Information',
};

class PriorityTile extends StatelessWidget {
  final Priority priority;
  final VoidCallback? onTap;
  final Widget? trailing;
  const PriorityTile({
    super.key,
    required this.priority,
    this.onTap,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    final (background, foreground) = priorityColors(priority.colorType);
    return Card(
      color: Colors.white,
      elevation: 0,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        leading: CircleAvatar(
          backgroundColor: background,
          foregroundColor: foreground,
          child: Icon(priorityIcon(priority.icon), size: 20),
        ),
        title: Text(
          priority.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: priority.subtitle.isEmpty ? null : Text(priority.subtitle),
        onTap: onTap,
        trailing: trailing,
      ),
    );
  }
}

class ManagePrioritiesScreen extends StatefulWidget {
  final PriorityBoard board;
  const ManagePrioritiesScreen({super.key, required this.board});
  @override
  State<ManagePrioritiesScreen> createState() => _ManagePrioritiesScreenState();
}

class _ManagePrioritiesScreenState extends State<ManagePrioritiesScreen> {
  late Future<List<Priority>> future = widget.board.priorities();
  bool deleting = false;
  String? error;

  Future<void> reload() async {
    final next = widget.board.priorities();
    setState(() => future = next);
    try {
      await next;
    } catch (_) {
      /* FutureBuilder displays recovery. */
    }
  }

  Future<void> form([Priority? priority]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => PriorityFormSheet(board: widget.board, priority: priority),
    );
    if (!mounted || saved != true) return;
    showFeedback(
      context,
      priority == null ? 'Priorité ajoutée.' : 'Priorité mise à jour.',
    );
    await reload();
  }

  Future<void> remove(Priority priority) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Supprimer cette priorité ?'),
        content: Text('« ${priority.title} » sera supprimée.'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      deleting = true;
      error = null;
    });
    try {
      await widget.board.deletePriority(priority);
      if (mounted) {
        showFeedback(context, 'Priorité supprimée.');
        await reload();
      }
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Priorités'),
      actions: [
        IconButton(
          tooltip: 'Actualiser',
          onPressed: deleting ? null : reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: deleting ? null : () => form(),
      icon: const Icon(Icons.add),
      label: const Text('Ajouter'),
    ),
    body: Column(
      children: [
        if (deleting) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(18),
            child: Text(error!, style: const TextStyle(color: AppColors.red)),
          ),
        Expanded(
          child: FutureBuilder<List<Priority>>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(userError(snap.error!)),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: reload,
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final items = snap.data ?? [];
              return RefreshIndicator(
                onRefresh: reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 100),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (items.isEmpty)
                      const EmptyState(
                        'Aucune priorité',
                        'Ajoutez les points à suivre pour la journée.',
                      ),
                    for (final priority in items)
                      PriorityTile(
                        priority: priority,
                        onTap: deleting ? null : () => form(priority),
                        trailing: PopupMenuButton<String>(
                          enabled: !deleting,
                          tooltip: 'Actions pour ${priority.title}',
                          onSelected: (action) => action == 'edit'
                              ? form(priority)
                              : remove(priority),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Modifier')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Supprimer'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class PriorityFormSheet extends StatefulWidget {
  final PriorityBoard board;
  final Priority? priority;
  const PriorityFormSheet({super.key, required this.board, this.priority});
  @override
  State<PriorityFormSheet> createState() => _PriorityFormSheetState();
}

class _PriorityFormSheetState extends State<PriorityFormSheet> {
  final key = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.priority?.title ?? '');
  late final subtitle = TextEditingController(
    text: widget.priority?.subtitle ?? '',
  );
  late String icon = widget.priority?.icon ?? 'warning';
  late String color = widget.priority?.colorType ?? 'danger';
  bool busy = false;
  String? error;
  bool get dirty =>
      title.text != (widget.priority?.title ?? '') ||
      subtitle.text != (widget.priority?.subtitle ?? '') ||
      icon != (widget.priority?.icon ?? 'warning') ||
      color != (widget.priority?.colorType ?? 'danger');
  @override
  void dispose() {
    title.dispose();
    subtitle.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !key.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.board.savePriority(
        widget.priority,
        icon: icon,
        title: title.text.trim(),
        subtitle: subtitle.text.trim(),
        colorType: color,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  static const _label = TextStyle(
    fontSize: 11,
    letterSpacing: 1.5,
    fontWeight: FontWeight.w700,
    color: AppColors.muted,
  );

  @override
  Widget build(BuildContext context) => DraftGuard(
    dirty: dirty,
    busy: busy,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: key,
        onChanged: () => setState(() {}),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.priority == null
                  ? 'Nouvelle priorité'
                  : 'Modifier la priorité',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    style: const TextStyle(color: AppColors.red),
                  ),
                ),
              ),
            TextFormField(
              controller: title,
              enabled: !busy,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Titre'),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Renseignez un titre.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: subtitle,
              enabled: !busy,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Détails',
                hintText: 'Ch. 305 · Urgent',
              ),
            ),
            const SizedBox(height: 16),
            const Text('ICÔNE', style: _label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in Priority.icons)
                  IconButton(
                    tooltip: name,
                    isSelected: name == icon,
                    onPressed: busy ? null : () => setState(() => icon = name),
                    style: IconButton.styleFrom(
                      backgroundColor: name == icon
                          ? AppColors.primary
                          : Colors.white,
                      foregroundColor: name == icon
                          ? Colors.white
                          : AppColors.primary,
                      side: const BorderSide(color: AppColors.border),
                    ),
                    icon: Icon(priorityIcon(name)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('TYPE', style: _label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final type in Priority.colorTypes)
                  ChoiceChip(
                    label: Text(priorityColorLabels[type]!),
                    selected: type == color,
                    avatar: CircleAvatar(
                      backgroundColor: priorityColors(type).$2,
                      radius: 6,
                    ),
                    onSelected: busy
                        ? null
                        : (_) => setState(() => color = type),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: busy ? null : save,
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.priority == null
                            ? 'Créer la priorité'
                            : 'Enregistrer',
                      ),
              ),
            ),
            TextButton(
              onPressed: busy ? null : () => Navigator.maybePop(context),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    ),
  );
}
