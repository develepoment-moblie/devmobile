import 'package:flutter/material.dart';
import '../../shared/custom/app_widgets.dart';
import '../../shared/custom/app_theme.dart';
import '../../shared/services/app_session.dart';
import '../../shared/models/app_user.dart';
import '../models/room_service.dart';
import '../services/service_desk_store.dart';

String serviceDate(Object? value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '—';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

Future<DateTime?> chooseServiceDate(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final day = await showDatePicker(
    context: context,
    initialDate: initial != null && initial.isAfter(now) ? initial : now,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 365)),
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial ?? now),
  );
  if (time == null) return null;
  return DateTime(day.year, day.month, day.day, time.hour, time.minute);
}

Future<String?> serviceText(
  BuildContext context,
  String title, {
  String initial = '',
  int max = 2000,
  bool required = true,
}) async {
  final controller = TextEditingController(text: initial);
  final form = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Form(
        key: form,
        child: TextFormField(
          controller: controller,
          maxLength: max,
          minLines: 2,
          maxLines: 5,
          validator: (v) => required && v!.trim().isEmpty
              ? 'Ce champ est obligatoire.'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Revenir'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return result;
}

Future<bool> serviceConfirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
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
    ) ??
    false;

class ServiceDeskScreen extends StatefulWidget {
  final AppSession session;
  const ServiceDeskScreen({super.key, required this.session});
  @override
  State<ServiceDeskScreen> createState() => _ServiceDeskScreenState();
}

class _ServiceDeskScreenState extends State<ServiceDeskScreen> {
  late final store = ServiceDeskStore(widget.session);
  List<Map<String, Object?>> rows = [];
  String kind = 'restaurant', query = '', status = 'all';
  bool archived = false, loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await store.records(archived: archived);
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
          loading = false;
          error = 'Impossible de charger les dossiers.';
        });
      }
    }
  }

  Future<void> create() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _RecordForm(store: store, kind: kind),
      ),
    );
    if (changed == true) await load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = rows
        .where(
          (r) =>
              r['kind'] == kind &&
              (status == 'all' || r['status'] == status) &&
              '${r['title']} ${r['guest_name']} ${r['id']}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(store.isGuest ? 'Mes services' : 'Gestion des services'),
        actions: [
          if (widget.session.user?.hasAnyRole(AppRole.management) ?? false)
            IconButton(
              tooltip: 'Gérer les créneaux',
              icon: const Icon(Icons.event_available),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SlotManagementScreen(store: store),
                  ),
                );
                await load();
              },
            ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: store.isGuest && !archived
          ? FloatingActionButton.extended(
              onPressed: create,
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle demande'),
            )
          : null,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Text(
                    store.isGuest
                        ? 'Tout pour votre séjour'
                        : 'Demandes et réservations',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in serviceKinds.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: kind == e.key,
                          onSelected: (_) => setState(() => kind = e.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Rechercher',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Statut'),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('Tous les statuts'),
                      ),
                      for (final e in serviceStatuses.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => status = v!),
                  ),
                  SwitchListTile(
                    title: const Text('Dossiers archivés'),
                    value: archived,
                    onChanged: (v) {
                      setState(() {
                        archived = v;
                        loading = true;
                      });
                      load();
                    },
                  ),
                  if (error != null)
                    TextButton(
                      onPressed: load,
                      child: Text('$error Réessayer'),
                    ),
                  if (visible.isEmpty && error == null)
                    const EmptyState(
                      'Aucun dossier',
                      'Les demandes de cette catégorie apparaîtront ici.',
                    ),
                  for (final row in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          title: Text('#${row['id']} · ${row['title']}'),
                          subtitle: Text(
                            '${row['guest_name']}\n${serviceStatuses[row['status']]} · ${serviceDate(row['created_at'])}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _RecordDetails(
                                  store: store,
                                  id: row['id'] as int,
                                ),
                              ),
                            );
                            await load();
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _RecordForm extends StatefulWidget {
  final ServiceDeskStore store;
  final String kind;
  final Map<String, Object?>? previous;
  const _RecordForm({required this.store, required this.kind, this.previous});
  @override
  State<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<_RecordForm> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(
    text: widget.previous?['title'] as String?,
  );
  late final details = TextEditingController(
    text: widget.previous?['details'] as String?,
  );
  late final units = TextEditingController(
    text: '${widget.previous?['units'] ?? 1}',
  );
  List<Map<String, Object?>> slots = [];
  int? selected;
  DateTime? due;
  bool busy = false, loading = true;
  String? error;
  bool get booking => {'restaurant', 'spa'}.contains(widget.kind);
  @override
  void initState() {
    super.initState();
    selected = widget.previous?['slot_id'] as int?;
    due = DateTime.tryParse('${widget.previous?['due_at']}')?.toLocal();
    load();
  }

  @override
  void dispose() {
    title.dispose();
    details.dispose();
    units.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final data = booking
          ? await widget.store.slots(kind: widget.kind)
          : <Map<String, Object?>>[];
      if (mounted) {
        setState(() {
          slots = data
              .where(
                (s) => DateTime.parse(
                  s['starts_at'] as String,
                ).isAfter(DateTime.now()),
              )
              .toList();
          if (!slots.any((s) => s['id'] == selected)) selected = null;
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Créneaux indisponibles. Réessayez.';
        });
      }
    }
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await widget.store.saveRecord(
        previous: widget.previous,
        kind: widget.kind,
        title: title.text,
        details: details.text,
        slotId: selected,
        units: int.parse(units.text),
        dueAt: due,
      );
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (e) {
      if (mounted) showFeedback(context, e.message);
    } catch (_) {
      if (mounted) {
        showFeedback(context, 'Enregistrement impossible. Réessayez.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.previous == null ? 'Créer' : 'Modifier'} · ${serviceKinds[widget.kind]}',
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  TextFormField(
                    controller: title,
                    maxLength: 100,
                    decoration: const InputDecoration(labelText: 'Objet'),
                    validator: (v) =>
                        v!.trim().isEmpty ? 'Objet obligatoire' : null,
                  ),
                  TextFormField(
                    controller: details,
                    maxLength: 2000,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'Détails'),
                    validator: (v) =>
                        v!.trim().isEmpty ? 'Détails obligatoires' : null,
                  ),
                  if (error != null)
                    TextButton(onPressed: load, child: Text(error!)),
                  if (booking) ...[
                    if (slots.isEmpty)
                      const Text(
                        'Aucun créneau disponible. Contactez la réception.',
                      ),
                    for (final slot in slots)
                      CheckboxListTile(
                        value: selected == slot['id'],
                        onChanged: busy
                            ? null
                            : (v) => setState(
                                () => selected = v == true
                                    ? slot['id'] as int
                                    : null,
                              ),
                        title: Text(
                          '${slot['name']} · ${serviceDate(slot['starts_at'])}',
                        ),
                        subtitle: Text(
                          'Fin : ${serviceDate(slot['ends_at'])}\n${(slot['capacity'] as int) - (slot['reserved'] as int)} places restantes · ${euros(slot['price_cents'] as int)} / personne',
                        ),
                      ),
                    TextFormField(
                      controller: units,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de personnes',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          (int.tryParse(v!) ?? 0) < 1 ||
                              (int.tryParse(v) ?? 21) > 20
                          ? 'Entre 1 et 20'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'La demande réserve des places et attend la confirmation de la réception. Aucun paiement automatique.',
                    ),
                  ],
                  if (!booking) ...[
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              final d = await chooseServiceDate(
                                context,
                                initial: due,
                              );
                              if (d != null && mounted) setState(() => due = d);
                            },
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        due == null
                            ? 'Horaire souhaité (facultatif)'
                            : serviceDate(due),
                      ),
                    ),
                    if (due != null)
                      TextButton(
                        onPressed: () => setState(() => due = null),
                        child: const Text('Retirer l’horaire'),
                      ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy || (booking && selected == null)
                        ? null
                        : save,
                    child: Text(busy ? 'Enregistrement…' : 'Enregistrer'),
                  ),
                ],
              ),
            ),
    ),
  );
}

class _RecordDetails extends StatefulWidget {
  final ServiceDeskStore store;
  final int id;
  const _RecordDetails({required this.store, required this.id});
  @override
  State<_RecordDetails> createState() => _RecordDetailsState();
}

class _RecordDetailsState extends State<_RecordDetails> {
  Map<String, Object?>? row, review;
  List<Map<String, Object?>> messages = [], audit = [];
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final record = await widget.store.accessible(
        widget.store.session.database.database,
        widget.id,
      );
      final thread = await widget.store.messages(widget.id);
      final rating = await widget.store.review(widget.id);
      final history = widget.store.isGuest
          ? <Map<String, Object?>>[]
          : await widget.store.history(widget.id);
      if (mounted) {
        setState(() {
          row = record;
          messages = thread;
          review = rating;
          audit = history;
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Dossier inaccessible. Réessayez.';
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
      await load();
    } catch (_) {
      if (mounted) showFeedback(context, 'Action impossible. Réessayez.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> transition(String next) async {
    final reason =
        {'cancelled', 'rejected'}.contains(next) && !widget.store.isGuest
        ? await serviceText(context, 'Motif obligatoire', max: 500)
        : '';
    if (reason == null || !mounted) return;
    if (!await serviceConfirm(
          context,
          'Changer le statut ?',
          serviceStatuses[next]!,
        ) ||
        !mounted) {
      return;
    }
    await perform(() => widget.store.status(row!, next, reason: reason));
  }

  Future<void> message([Map<String, Object?>? previous]) async {
    final body = await serviceText(
      context,
      previous == null ? 'Nouveau message' : 'Modifier le message',
      initial: previous?['body'] as String? ?? '',
    );
    if (body != null && mounted) {
      await perform(
        () => widget.store.saveMessage(widget.id, body, previous: previous),
      );
    }
  }

  Future<void> assign() async {
    try {
      final people = await widget.store.session.staff.users(
        roles: {
          AppRole.receptionist,
          AppRole.staff,
          AppRole.supervisor,
          AppRole.maintenance,
          AppRole.manager,
          AppRole.admin,
        },
      );
      if (!mounted) return;
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Attribuer le dossier'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Sans responsable'),
            ),
            for (final person in people)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, person.id),
                child: Text('${person.fullName} · ${person.roleLabel}'),
              ),
          ],
        ),
      );
      if (selected != null && mounted) {
        await perform(
          () => widget.store.assign(row!, selected.isEmpty ? null : selected),
        );
      }
    } catch (_) {
      if (mounted) showFeedback(context, 'Liste du personnel indisponible.');
    }
  }

  Future<void> rate() async {
    int rating = review?['rating'] as int? ?? 5;
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Évaluer le service'),
          content: DropdownButton<int>(
            value: rating,
            items: [
              for (var i = 1; i <= 5; i++)
                DropdownMenuItem(value: i, child: Text('$i / 5')),
            ],
            onChanged: (v) => update(() => rating = v!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Revenir'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, rating),
              child: const Text('Continuer'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final body = await serviceText(
      context,
      'Votre avis',
      initial: review?['body'] as String? ?? '',
      max: 1000,
    );
    if (body != null && mounted) {
      await perform(
        () => widget.store.saveReview(
          widget.id,
          selected,
          body,
          previous: review,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = row;
    final closed =
        r == null ||
        {'completed', 'cancelled', 'rejected'}.contains(r['status']) ||
        r['archived'] == 1;
    return Scaffold(
      appBar: AppBar(
        title: Text('Dossier #${widget.id}'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: TextButton(onPressed: load, child: Text(error!)),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  '${r!['title']}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text('${serviceKinds[r['kind']]} · ${r['guest_name']}'),
                Chip(
                  label: Text(serviceStatuses[r['status']] ?? '${r['status']}'),
                ),
                Text('${r['details']}', style: const TextStyle(height: 1.6)),
                const SizedBox(height: 12),
                if (r['slot_id'] != null)
                  Text(
                    '${r['slot_name']} · ${serviceDate(r['starts_at'])} → ${serviceDate(r['ends_at'])} · ${r['units']} personne(s) · ${euros(r['price_cents'] as int)}',
                  ),
                if (r['due_at'] != null)
                  Text('Horaire souhaité : ${serviceDate(r['due_at'])}'),
                if (r['reason'] != null) Text('Motif : ${r['reason']}'),
                if (r['assigned_to'] != null)
                  Text('Responsable : ${r['assigned_to']}'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.store.isGuest &&
                        r['status'] == 'pending' &&
                        !closed) ...[
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _RecordForm(
                                      store: widget.store,
                                      kind: r['kind'] as String,
                                      previous: r,
                                    ),
                                  ),
                                );
                                await load();
                              },
                        child: const Text('Modifier'),
                      ),
                      OutlinedButton(
                        onPressed: busy ? null : () => transition('cancelled'),
                        child: const Text('Annuler'),
                      ),
                    ],
                    if (!widget.store.isGuest && !closed) ...[
                      for (final next in switch (r['status']) {
                        'pending' => ['confirmed', 'rejected'],
                        'confirmed' => ['in_progress', 'cancelled'],
                        'in_progress' => ['completed', 'cancelled'],
                        _ => <String>[],
                      })
                        FilledButton(
                          onPressed: busy ? null : () => transition(next),
                          child: Text(serviceStatuses[next]!),
                        ),
                    ],
                    if (!widget.store.isGuest &&
                        {
                          'completed',
                          'cancelled',
                          'rejected',
                        }.contains(r['status']))
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () async {
                                if (await serviceConfirm(
                                  context,
                                  'Archivage',
                                  r['archived'] == 1
                                      ? 'Restaurer ce dossier ?'
                                      : 'Archiver ce dossier ?',
                                )) {
                                  await perform(
                                    () => widget.store.archiveRecord(
                                      r,
                                      r['archived'] != 1,
                                    ),
                                  );
                                }
                              },
                        child: Text(
                          r['archived'] == 1 ? 'Restaurer' : 'Archiver',
                        ),
                      ),
                  ],
                ),
                if (!widget.store.isGuest && !closed)
                  OutlinedButton.icon(
                    onPressed: busy ? null : assign,
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('Attribuer le dossier'),
                  ),
                const Divider(height: 32),
                Text(
                  'Conversation',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final m in messages)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${m['author_name']} · ${serviceDate(m['updated_at'])}',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                          Text(
                            m['deleted'] == 1
                                ? 'Message supprimé'
                                : '${m['body']}',
                          ),
                          if (m['author_id'] == widget.store.session.user?.id &&
                              m['deleted'] != 1 &&
                              !closed)
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: busy ? null : () => message(m),
                                  child: const Text('Modifier'),
                                ),
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          if (await serviceConfirm(
                                            context,
                                            'Supprimer ce message ?',
                                            'Le contenu sera retiré de la conversation.',
                                          )) {
                                            await perform(
                                              () => widget.store.saveMessage(
                                                widget.id,
                                                '',
                                                previous: m,
                                                delete: true,
                                              ),
                                            );
                                          }
                                        },
                                  child: const Text('Supprimer'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                if (!closed)
                  FilledButton.icon(
                    onPressed: busy ? null : message,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Écrire un message'),
                  ),
                if (review != null) ...[
                  const Divider(height: 32),
                  Text('Avis : ${review!['rating']} / 5'),
                  Text('${review!['body']}'),
                ],
                if (widget.store.isGuest && r['status'] == 'completed') ...[
                  TextButton(
                    onPressed: busy ? null : rate,
                    child: Text(
                      review == null ? 'Laisser un avis' : 'Modifier mon avis',
                    ),
                  ),
                  if (review != null)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (await serviceConfirm(
                                context,
                                'Supprimer mon avis ?',
                                'Cette action retire votre avis.',
                              )) {
                                await perform(
                                  () => widget.store.saveReview(
                                    widget.id,
                                    1,
                                    '',
                                    previous: review,
                                    delete: true,
                                  ),
                                );
                              }
                            },
                      child: const Text('Supprimer mon avis'),
                    ),
                ],
                if (!widget.store.isGuest)
                  ExpansionTile(
                    title: const Text('Historique des actions'),
                    children: [
                      for (final a in audit)
                        ListTile(
                          title: Text('${a['action']}'),
                          subtitle: Text(
                            '${a['actor_id']} · ${serviceDate(a['created_at'])}',
                          ),
                        ),
                    ],
                  ),
                if (busy) const LinearProgressIndicator(),
              ],
            ),
    );
  }
}

class SlotManagementScreen extends StatefulWidget {
  final ServiceDeskStore store;
  const SlotManagementScreen({super.key, required this.store});
  @override
  State<SlotManagementScreen> createState() => _SlotManagementScreenState();
}

class _SlotManagementScreenState extends State<SlotManagementScreen> {
  List<Map<String, Object?>> slots = [];
  bool archived = false, loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await widget.store.slots(archived: archived);
      if (mounted) {
        setState(() {
          slots = rows;
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

  Future<void> edit([Map<String, Object?>? slot]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SlotForm(store: widget.store, previous: slot),
      ),
    );
    await load();
  }

  Future<void> archive(Map<String, Object?> slot) async {
    if (!await serviceConfirm(
          context,
          'Créneau',
          archived ? 'Restaurer ce créneau ?' : 'Archiver ce créneau ?',
        ) ||
        !mounted ||
        busy) {
      return;
    }
    setState(() => busy = true);
    try {
      await widget.store.archiveSlot(slot, !archived);
      await load();
    } on StateError catch (e) {
      if (mounted) showFeedback(context, e.message);
    } catch (_) {
      if (mounted) showFeedback(context, 'Modification impossible.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Créneaux restaurant et spa')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: busy ? null : () => edit(),
      icon: const Icon(Icons.add),
      label: const Text('Créer un créneau'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            children: [
              const Text(
                'La capacité s’applique à ce créneau. Évitez de créer plusieurs créneaux pour la même ressource au même horaire.',
              ),
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
              if (slots.isEmpty && error == null)
                const EmptyState(
                  'Aucun créneau',
                  'Créez des horaires et capacités pour ouvrir les réservations.',
                ),
              for (final s in slots)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${serviceKinds[s['kind']]} · ${s['name']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${serviceDate(s['starts_at'])} → ${serviceDate(s['ends_at'])}',
                        ),
                        Text(
                          '${s['reserved']} / ${s['capacity']} places · ${euros(s['price_cents'] as int)} / personne',
                        ),
                        Wrap(
                          children: [
                            if (!archived)
                              TextButton(
                                onPressed: busy ? null : () => edit(s),
                                child: const Text('Modifier'),
                              ),
                            TextButton(
                              onPressed: busy ? null : () => archive(s),
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

class _SlotForm extends StatefulWidget {
  final ServiceDeskStore store;
  final Map<String, Object?>? previous;
  const _SlotForm({required this.store, this.previous});
  @override
  State<_SlotForm> createState() => _SlotFormState();
}

class _SlotFormState extends State<_SlotForm> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.previous?['name'] as String?,
  );
  late final capacity = TextEditingController(
    text: '${widget.previous?['capacity'] ?? 1}',
  );
  late final price = TextEditingController(
    text: ((widget.previous?['price_cents'] as int? ?? 0) / 100)
        .toStringAsFixed(2),
  );
  late String kind = widget.previous?['kind'] as String? ?? 'restaurant';
  late DateTime? start = DateTime.tryParse(
        '${widget.previous?['starts_at']}',
      )?.toLocal(),
      end = DateTime.tryParse('${widget.previous?['ends_at']}')?.toLocal();
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    capacity.dispose();
    price.dispose();
    super.dispose();
  }

  int? get cents {
    final s = price.text.trim().replaceAll(',', '.');
    return RegExp(r'^\d{1,5}(\.\d{1,2})?$').hasMatch(s)
        ? (double.parse(s) * 100).round()
        : null;
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (start == null || end == null) {
      showFeedback(context, 'Choisissez les horaires de début et de fin.');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.store.saveSlot(
        previous: widget.previous,
        kind: kind,
        name: name.text,
        start: start!,
        end: end!,
        capacity: int.parse(capacity.text),
        priceCents: cents!,
      );
      if (mounted) Navigator.pop(context);
    } on StateError catch (e) {
      if (mounted) showFeedback(context, e.message);
    } catch (_) {
      if (mounted) showFeedback(context, 'Enregistrement impossible.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.previous == null ? 'Créer un créneau' : 'Modifier le créneau',
        ),
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String>(
              initialValue: kind,
              items: [
                for (final k in ['restaurant', 'spa'])
                  DropdownMenuItem(value: k, child: Text(serviceKinds[k]!)),
              ],
              onChanged: busy ? null : (v) => setState(() => kind = v!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: name,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Établissement, salle ou cabine',
              ),
              validator: (v) => v!.trim().isEmpty ? 'Nom obligatoire' : null,
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final d = await chooseServiceDate(
                        context,
                        initial: start,
                      );
                      if (d != null && mounted) setState(() => start = d);
                    },
              child: Text(
                start == null
                    ? 'Choisir le début'
                    : 'Début : ${serviceDate(start)}',
              ),
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final d = await chooseServiceDate(context, initial: end);
                      if (d != null && mounted) setState(() => end = d);
                    },
              child: Text(
                end == null ? 'Choisir la fin' : 'Fin : ${serviceDate(end)}',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: capacity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Capacité en personnes',
              ),
              validator: (v) =>
                  (int.tryParse(v!) ?? 0) < 1 || (int.tryParse(v) ?? 501) > 500
                  ? 'Entre 1 et 500'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Tarif par personne (€)',
              ),
              validator: (_) => cents == null || cents! > 1000000
                  ? 'Tarif entre 0 et 10 000 €, deux décimales maximum'
                  : null,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Enregistrement…' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    ),
  );
}
