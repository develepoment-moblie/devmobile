import 'package:flutter/material.dart';
import '../../shared/custom/app_widgets.dart';
import '../../shared/models/app_user.dart';
import '../services/guest_service_store.dart';
import 'service_desk_screen.dart'
    show chooseServiceDate, serviceDate, serviceConfirm;

class ServiceRoomScreen extends StatefulWidget {
  final GuestServiceStore store;
  const ServiceRoomScreen({super.key, required this.store});
  @override
  State<ServiceRoomScreen> createState() => _ServiceRoomScreenState();
}

class _ServiceRoomScreenState extends State<ServiceRoomScreen> {
  List<Map<String, Object?>> stays = [];
  List<AppUser> guests = [];
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await widget.store.stays();
      final people = await widget.store.session.staff.users(
        roles: {AppRole.guest},
      );
      if (mounted) {
        setState(() {
          stays = rows;
          guests = people;
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

  Future<void> edit([Map<String, Object?>? stay]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _RoomForm(store: widget.store, guests: guests, previous: stay),
      ),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Chambres des clients'),
      actions: [
        IconButton(
          onPressed: load,
          tooltip: 'Actualiser',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: busy ? null : () => edit(),
      label: const Text('Associer une chambre'),
      icon: const Icon(Icons.add),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            children: [
              const Text(
                'Vérifiez le séjour et la chambre dans le registre de réception avant de les associer. Cette association autorise les commandes en chambre jusqu’au départ indiqué.',
              ),
              if (error != null)
                TextButton(onPressed: load, child: Text('$error Réessayer')),
              if (guests.isEmpty)
                const Text('Aucun client dans l’annuaire utilisateurs.'),
              for (final s in stays)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s['guest_name']} · Chambre ${s['room_number']}',
                        ),
                        Text('Référence : ${s['id']}'),
                        Text(
                          s['active'] != 1
                              ? 'Inactive'
                              : 'Départ : ${serviceDate(s['valid_until'])}',
                        ),
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: busy ? null : () => edit(s),
                              child: const Text('Modifier / renouveler'),
                            ),
                            if (s['active'] == 1)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () async {
                                        if (!await serviceConfirm(
                                              context,
                                              'Désactiver cette association ?',
                                              'Le client ne pourra plus passer de nouvelle commande en chambre.',
                                            ) ||
                                            !mounted) {
                                          return;
                                        }
                                        setState(() => busy = true);
                                        try {
                                          await widget.store.deactivateStay(
                                            s['guest_id'] as String,
                                          );
                                          await load();
                                        } catch (_) {
                                          if (context.mounted) {
                                            showFeedback(
                                              context,
                                              'Désactivation impossible.',
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() => busy = false);
                                          }
                                        }
                                      },
                                child: const Text('Désactiver'),
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

class _RoomForm extends StatefulWidget {
  final GuestServiceStore store;
  final List<AppUser> guests;
  final Map<String, Object?>? previous;
  const _RoomForm({required this.store, required this.guests, this.previous});
  @override
  State<_RoomForm> createState() => _RoomFormState();
}

class _RoomFormState extends State<_RoomForm> {
  final form = GlobalKey<FormState>();
  late final reference = TextEditingController(
    text: widget.previous?['id'] as String?,
  );
  late final room = TextEditingController(
    text: widget.previous?['room_number'] as String?,
  );
  late String? guest =
      widget.guests.any((g) => g.id == widget.previous?['guest_id'])
      ? (widget.previous?['guest_id'] as String?)
      : null;
  late DateTime? departure = DateTime.tryParse(
    '${widget.previous?['valid_until']}',
  )?.toLocal();
  bool busy = false;
  @override
  void dispose() {
    reference.dispose();
    room.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (departure == null) {
      showFeedback(context, 'Choisissez la date et l’heure de départ.');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.store.saveStay(
        guest: guest!,
        reference: reference.text,
        room: room.text,
        validUntil: departure!,
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
      appBar: AppBar(title: const Text('Vérifier une chambre')),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String>(
              initialValue: guest,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Client'),
              items: [
                for (final g in widget.guests)
                  DropdownMenuItem(value: g.id, child: Text(g.fullName)),
              ],
              onChanged: busy ? null : (v) => guest = v,
              validator: (v) => v == null ? 'Choisissez un client.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: reference,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Référence du séjour',
              ),
              validator: (v) =>
                  v!.trim().isEmpty ? 'Référence obligatoire' : null,
            ),
            TextFormField(
              controller: room,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Chambre'),
              validator: (v) =>
                  v!.trim().isEmpty ? 'Chambre obligatoire' : null,
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final date = await chooseServiceDate(
                        context,
                        initial: departure,
                      );
                      if (date != null && mounted) {
                        setState(() => departure = date);
                      }
                    },
              child: Text(
                departure == null
                    ? 'Date et heure de départ'
                    : serviceDate(departure),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Enregistrement…' : 'Confirmer l’association'),
            ),
          ],
        ),
      ),
    ),
  );
}
