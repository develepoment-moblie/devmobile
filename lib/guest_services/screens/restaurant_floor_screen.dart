import 'package:flutter/material.dart';
import '../../shared/custom/app_widgets.dart';
import '../../shared/models/app_user.dart';
import '../services/service_desk_store.dart';
import 'service_desk_screen.dart'
    show serviceConfirm, serviceDate, ServiceRecordForm;
import 'dining_floor_grid.dart';

class RestaurantFloorScreen extends StatefulWidget {
  final ServiceDeskStore store;
  const RestaurantFloorScreen({super.key, required this.store});

  @override
  State<RestaurantFloorScreen> createState() => _RestaurantFloorScreenState();
}

class _RestaurantFloorScreenState extends State<RestaurantFloorScreen> {
  late Future<
    ({List<Map<String, Object?>> tables, List<Map<String, Object?>> arrivals})
  >
  data = load();
  bool busy = false;

  Future<
    ({List<Map<String, Object?>> tables, List<Map<String, Object?>> arrivals})
  >
  load() async => (
    tables: await widget.store.diningTables(),
    arrivals: await widget.store.restaurantArrivals(),
  );

  void refresh() {
    setState(() {
      data = load();
    });
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } on StateError catch (error) {
      if (mounted) showFeedback(context, error.message);
    } catch (_) {
      if (mounted) showFeedback(context, 'Action impossible. Réessayez.');
    } finally {
      if (mounted) {
        busy = false;
        refresh();
      }
    }
  }

  Future<void> seat(
    Map<String, Object?> party,
    List<Map<String, Object?>> available,
  ) async {
    final booked = party['dining_table_id'];
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => _SeatingDialog(
        booked: booked as int?,
        available: available,
        choices: widget.store.restaurantTableChoicesAt(
          DateTime.parse(party['starts_at'] as String),
          end: DateTime.parse(party['ends_at'] as String),
          recordId: party['id'] as int,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await run(
      () => widget.store.seatRestaurantParty(party['id'] as int, selected),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Restaurant · Plan de salle'),
      actions: [
        IconButton(
          tooltip: 'Actualiser',
          onPressed: busy ? null : refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder(
      future: data,
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: refresh,
              child: const Text('Chargement impossible. Réessayer'),
            ),
          );
        }
        final floor = snapshot.data!;
        final canBook =
            widget.store.session.user?.hasAnyRole(AppRole.management) ?? false;
        final free = floor.tables
            .where((table) => table['record_id'] == null)
            .toList();
        final reserved = free.where((table) => table['reserved'] == 1).length;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Service en salle',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '${free.length - reserved} libre(s) · $reserved réservée(s) · ${floor.tables.length - free.length} occupée(s)',
            ),
            if (canBook)
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final saved = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ServiceRecordForm(
                              store: widget.store,
                              kind: 'restaurant',
                            ),
                          ),
                        );
                        if (mounted && saved == true) refresh();
                      },
                icon: const Icon(Icons.event_available),
                label: const Text('Réserver une table'),
              ),
            const SizedBox(height: 12),
            DiningFloorGrid(
              tables: floor.tables
                  .where((table) => table['shape'] != null)
                  .toList(),
              status: (table) {
                if (table['record_id'] != null) return 'Occupée';
                return table['reserved'] == 1 ? 'Réservée' : 'Libre';
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Arrivées et attente',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (floor.arrivals.isEmpty)
              const Text('Aucune réservation confirmée à accueillir.'),
            for (final party in floor.arrivals)
              Builder(
                builder: (context) {
                  final arrived = party['arrived_at'] != null;
                  final fits = free
                      .where(
                        (table) =>
                            (table['seats'] as int) >= (party['units'] as int),
                      )
                      .toList();
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${party['guest_name']} · ${party['units']} personne(s)',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            arrived
                                ? 'Arrivé · en attente de table'
                                : serviceDate(party['starts_at']),
                          ),
                          if (party['dining_table_name'] != null)
                            Text(
                              'Table réservée · ${party['dining_table_name']}',
                            ),
                          if (!arrived)
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => run(
                                      () => widget.store
                                          .registerRestaurantArrival(
                                            party['id'] as int,
                                          ),
                                    ),
                              child: const Text('Marquer arrivé'),
                            )
                          else if (fits.isEmpty)
                            const Text(
                              'Aucune table libre adaptée. Le groupe reste en attente.',
                            )
                          else
                            FilledButton(
                              onPressed: busy ? null : () => seat(party, fits),
                              child: Text(
                                party['dining_table_id'] == null
                                    ? 'Placer le groupe'
                                    : 'Installer ou changer de table',
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 16),
            Text('Tables', style: Theme.of(context).textTheme.titleLarge),
            if (floor.tables.isEmpty)
              const Text(
                'La direction doit configurer les tables de la salle.',
              ),
            for (final table in floor.tables)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${table['name']} · ${table['seats']} places',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        table['record_id'] == null
                            ? (table['reserved'] == 1 ? 'Réservée' : 'Libre')
                            : 'Occupée · ${table['guest_name']} (${table['units']})',
                      ),
                      if (table['record_id'] != null)
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  final confirmed = await serviceConfirm(
                                    context,
                                    'Libérer la table ?',
                                    'Le service de ce groupe sera clôturé.',
                                  );
                                  if (confirmed && mounted) {
                                    await run(
                                      () =>
                                          widget.store.finishRestaurantService(
                                            table['record_id'] as int,
                                          ),
                                    );
                                  }
                                },
                          child: const Text('Terminer et libérer'),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _SeatingDialog extends StatelessWidget {
  const _SeatingDialog({
    required this.booked,
    required this.available,
    required this.choices,
  });

  final int? booked;
  final List<Map<String, Object?>> available;
  final Future<List<Map<String, Object?>>> choices;

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: const Text('Installer le groupe'),
    children: [
      FutureBuilder(
        future: choices,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ListTile(
              title: Text('Tables indisponibles. Réessayez.'),
            );
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final eligibleIds = {
            for (final table in snapshot.data!)
              if (table['reserved'] == 0) table['id'],
          };
          final eligible = available
              .where((table) => eligibleIds.contains(table['id']))
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (eligible.isEmpty)
                const ListTile(
                  title: Text(
                    'Aucune table adaptée disponible pour ce créneau.',
                  ),
                ),
              for (final table in eligible.where(
                (table) => table['id'] == booked,
              ))
                option(context, table),
              for (final table in eligible.where(
                (table) => table['id'] != booked,
              ))
                option(context, table),
            ],
          );
        },
      ),
    ],
  );

  Widget option(
    BuildContext context,
    Map<String, Object?> table,
  ) => SimpleDialogOption(
    onPressed: () => Navigator.pop(context, table['id'] as int),
    child: Text(
      '${table['name']} · ${table['seats']} places${table['id'] == booked ? ' · réservée par le client' : ''}',
    ),
  );
}
