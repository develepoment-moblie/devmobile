import 'package:flutter/material.dart';

import '../../shared/custom/app_widgets.dart';
import '../../shared/custom/draft_guard.dart';
import '../../shared/custom/nova_icon.dart';
import '../models/hotel_data.dart';
import '../models/room.dart';

class AssignTaskScreen extends StatefulWidget {
  final HotelData data;
  final Room? room;
  const AssignTaskScreen({super.key, required this.data, this.room});
  @override
  State<AssignTaskScreen> createState() => _AssignTaskScreenState();
}

class _AssignTaskScreenState extends State<AssignTaskScreen> {
  final formKey = GlobalKey<FormState>();
  final noteController = TextEditingController();
  final scroll = ScrollController();
  Room? room;
  String? employee;
  bool urgent = false;
  bool saving = false;
  String? error;
  int? expectedVersion;
  int roomSelectorRevision = 0;
  String? initialEmployee;
  String initialNote = '';
  bool initialUrgent = false;
  bool get fieldsChanged =>
      employee != initialEmployee ||
      noteController.text != initialNote ||
      urgent != initialUrgent;
  bool get dirty => room != widget.room || fieldsChanged;
  void loadRoom(Room? value) {
    room = value;
    expectedVersion = value?.version;
    employee = widget.data.isConnected ? value?.employeeId : value?.employee;
    urgent = value?.urgent ?? false;
    noteController.text = value?.note ?? '';
    initialEmployee = employee;
    initialNote = noteController.text;
    initialUrgent = urgent;
  }

  void updated() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    loadRoom(widget.room);
    noteController.addListener(updated);
    widget.data.addListener(updated);
  }

  @override
  void dispose() {
    widget.data.removeListener(updated);
    noteController.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eligible = widget.data.rooms
        .where(
          (r) =>
              r == room ||
              r.needsCleaning &&
                  (r.cleaning == CleaningStatus.waiting ||
                      r.cleaning == CleaningStatus.inProgress),
        )
        .toList();
    final options = Map<String, String>.from(
      widget.data.isConnected
          ? widget.data.agentOptions
          : {for (final name in widget.data.employees) name: name},
    );
    if (employee != null && !options.containsKey(employee)) {
      options[employee!] = 'Agent indisponible';
    }
    return DraftGuard(
      dirty: dirty,
      busy: saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Attribuer une tâche')),
        body: Form(
          key: formKey,
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(18),
            children: [
              if (saving) const LinearProgressIndicator(),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const StaffBanner(
                title: 'Chaque détail compte.',
                label: 'HOUSEKEEPING',
              ),
              const SizedBox(height: 24),
              if (eligible.isEmpty)
                const EmptyState(
                  'Toutes les tâches sont attribuées',
                  'Aucune chambre ne nécessite d’attribution.',
                ),
              DropdownButtonFormField<Room>(
                key: ValueKey('room-${room?.number}-$roomSelectorRevision'),
                initialValue: room,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Chambre'),
                items: eligible
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text('Chambre ${r.number} · ${r.cleaningLabel}'),
                      ),
                    )
                    .toList(),
                validator: (value) =>
                    value == null ? 'Choisissez une chambre.' : null,
                onChanged: saving
                    ? null
                    : (value) async {
                        if (value == room) return;
                        if (fieldsChanged && !await confirmDiscard(context)) {
                          if (mounted) setState(() => roomSelectorRevision++);
                          return;
                        }
                        if (mounted) setState(() => loadRoom(value));
                      },
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: ValueKey('agent-${room?.number}'),
                isExpanded: true,
                initialValue: employee,
                decoration: const InputDecoration(labelText: 'Agent d’étage'),
                items: options.entries
                    .map(
                      (agent) => DropdownMenuItem(
                        value: agent.key,
                        enabled:
                            !widget.data.isConnected ||
                            widget.data.agentOptions.containsKey(agent.key),
                        child: Text(agent.value),
                      ),
                    )
                    .toList(),
                validator: (value) => value == null
                    ? 'Choisissez un agent.'
                    : widget.data.isConnected &&
                          !widget.data.agentOptions.containsKey(value)
                    ? 'Cet agent n’est plus disponible. Choisissez un autre agent.'
                    : null,
                onChanged: saving
                    ? null
                    : (value) => setState(() => employee = value),
              ),
              const SizedBox(height: 20),
              if (options.isEmpty)
                const Text(
                  'Aucun agent actif. Demandez au Manager de créer un compte Agent d’étage.',
                ),
              TextFormField(
                controller: noteController,
                enabled: !saving,
                maxLines: 3,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Consignes',
                  hintText:
                      'Départ VIP, heure d’arrivée, attention particulière…',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tâche urgente'),
                subtitle: const Text('À traiter en priorité'),
                value: urgent,
                onChanged: saving
                    ? null
                    : (value) => setState(() => urgent = value),
              ),
              const SizedBox(height: 24),
              NovaButton(
                'Attribuer la tâche',
                symbol: NovaSymbol.check,
                onPressed:
                    saving || !widget.data.isSupervisor || eligible.isEmpty
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setState(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await widget.data.assign(
                            room!,
                            employee!,
                            noteController.text.trim(),
                            urgent,
                            version: expectedVersion,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(
                            context,
                            'Tâche attribuée à ${widget.data.staffIds[employee] ?? employee} · chambre ${room!.number}',
                          );
                        } catch (e) {
                          if (mounted) {
                            setState(() {
                              error = e.toString();
                              expectedVersion = room?.version;
                            });
                            if (scroll.hasClients) {
                              scroll.animateTo(
                                0,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                              );
                            }
                          }
                        } finally {
                          if (mounted) setState(() => saving = false);
                        }
                      },
              ),
              TextButton(
                onPressed: saving ? null : () => Navigator.maybePop(context),
                child: const Text('Annuler'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
