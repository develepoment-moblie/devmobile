import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/add_rooms_sheet.dart';
import '../custom/catalog_widgets.dart';
import '../custom/draft_guard.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/roomcard.dart';
import '../models/catalog_data.dart';
import '../models/room.dart';
import '../services/room_catalog_backend.dart';
import 'category_tasks_screen.dart';
import 'floor_screen.dart';

// The Manager's catalog: the hotel's floors, each opening its rooms.
class ManageRoomsScreen extends StatefulWidget {
  final RoomCatalogBackend backend;
  const ManageRoomsScreen({super.key, required this.backend});
  @override
  State<ManageRoomsScreen> createState() => _ManageRoomsScreenState();
}

class _ManageRoomsScreenState extends State<ManageRoomsScreen> {
  late final catalog = CatalogData(widget.backend);
  final query = TextEditingController();

  @override
  void initState() {
    super.initState();
    catalog.addListener(_changed);
    catalog.load();
  }

  @override
  void dispose() {
    catalog.removeListener(_changed);
    catalog.dispose();
    query.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> addRooms() async {
    final created = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => AddRoomsSheet(catalog: catalog),
    );
    if (mounted && created != null) {
      showFeedback(
        context,
        created == 1
            ? 'Chambre créée · nettoyage requis'
            : '$created chambres créées · nettoyage requis',
      );
    }
  }

  void open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final snapshot = catalog.snapshot;
    final term = query.text.trim().toLowerCase();
    final found = term.isEmpty
        ? const <Room>[]
        : [
            for (final r in catalog.rooms)
              if (r.number.contains(term) ||
                  r.category.toLowerCase().contains(term))
                r,
          ];
    final counts = RoomCounts.of(catalog.rooms);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Étages et chambres'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: catalog.loading ? null : catalog.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: snapshot == null ? null : addRooms,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter des chambres'),
      ),
      body: RefreshIndicator(
        onRefresh: catalog.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
          children: [
            if (catalog.loading && snapshot != null)
              const LinearProgressIndicator(),
            if (catalog.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Text(
                      catalog.error!,
                      style: const TextStyle(color: AppColors.red),
                    ),
                    TextButton(
                      onPressed: catalog.load,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            if (snapshot == null && catalog.error == null)
              const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (snapshot != null) ...[
              FadeSlideIn(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: AppGradients.hero,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'L’HÔTEL',
                        style: TextStyle(
                          color: AppColors.gold.withValues(alpha: .95),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          AnimatedCount(
                            counts.total,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                'chambres sur ${snapshot.floors.length} étage${snapshot.floors.length > 1 ? 's' : ''}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      StatusBar(counts),
                      const SizedBox(height: 10),
                      _LightLegend(counts),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          open(CategoryTasksScreen(catalog: catalog)),
                      icon: const Icon(Icons.checklist),
                      label: const Text('Tâches'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          open(ArchivedRoomsScreen(catalog: catalog)),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text(
                        'Archives · ${snapshot.archivedRooms.length}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: query,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Numéro ou catégorie',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer la recherche',
                          onPressed: () => setState(query.clear),
                          icon: const Icon(Icons.clear),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              if (term.isNotEmpty) ...[
                Text(
                  '${found.length} résultat${found.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                if (found.isEmpty)
                  const EmptyState(
                    'Aucune chambre trouvée',
                    'Modifiez ou effacez la recherche.',
                  ),
                for (final (i, room) in found.indexed)
                  FadeSlideIn(
                    key: ValueKey('search-${room.number}'),
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Roomcard(
                        room: room,
                        cleaning: false,
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) =>
                              RoomSheet(catalog: catalog, number: room.number),
                        ),
                      ),
                    ),
                  ),
              ] else ...[
                const Text(
                  'Étages',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (snapshot.floors.isEmpty)
                  const EmptyState(
                    'Aucun étage',
                    'Ajoutez des chambres : leur étage apparaîtra ici.',
                  ),
                for (final (i, floor) in snapshot.floors.indexed)
                  FadeSlideIn(
                    index: i,
                    child: _FloorCard(
                      name: catalog.floorName(floor),
                      counts: RoomCounts.of(catalog.roomsOn(floor)),
                      onTap: () =>
                          open(FloorScreen(catalog: catalog, floor: floor)),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _LightLegend extends StatelessWidget {
  final RoomCounts counts;
  const _LightLegend(this.counts);
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 6,
    children: [
      for (final (label, count) in [
        ('Libres', counts.ready),
        ('À nettoyer', counts.toClean),
        ('Occupées', counts.occupied),
        ('Maintenance', counts.maintenance),
      ])
        Text(
          '$label $count',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
    ],
  );
}

class _FloorCard extends StatelessWidget {
  final String name;
  final RoomCounts counts;
  final VoidCallback onTap;
  const _FloorCard({
    required this.name,
    required this.counts,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: PressableScale(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${counts.total} chambre${counts.total == 1 ? '' : 's'}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, color: AppColors.primary),
                ],
              ),
              const SizedBox(height: 10),
              StatusBar(counts, height: 8),
              const SizedBox(height: 8),
              StatusLegend(counts),
            ],
          ),
        ),
      ),
    ),
  );
}

// Archived rooms, with restoration.
class ArchivedRoomsScreen extends StatefulWidget {
  final CatalogData catalog;
  const ArchivedRoomsScreen({super.key, required this.catalog});
  @override
  State<ArchivedRoomsScreen> createState() => _ArchivedRoomsScreenState();
}

class _ArchivedRoomsScreenState extends State<ArchivedRoomsScreen> {
  bool busy = false;
  String? error;

  Future<void> restore(Room room) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.catalog.change(RoomCatalogAction.restore, {
        'number': room.number,
        'version': room.version,
      });
      if (mounted) {
        showFeedback(context, 'Chambre ${room.number} restaurée · à nettoyer');
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = widget.catalog.snapshot?.archivedRooms ?? const <Room>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Chambres archivées')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(error!, style: const TextStyle(color: AppColors.red)),
          if (rooms.isEmpty)
            const EmptyState(
              'Aucune chambre archivée',
              'Les chambres retirées du planning apparaîtront ici.',
            ),
          for (final (i, room) in rooms.indexed)
            FadeSlideIn(
              index: i,
              child: Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(
                    'Chambre ${room.number}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${room.category} · ${widget.catalog.floorName(room.floor)}',
                  ),
                  trailing: TextButton.icon(
                    onPressed: busy ? null : () => restore(room),
                    icon: const Icon(Icons.unarchive_outlined),
                    label: const Text('Restaurer'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RoomFormSheet extends StatefulWidget {
  final RoomCatalogBackend backend;
  final Room? room;
  const RoomFormSheet({super.key, required this.backend, this.room});
  @override
  State<RoomFormSheet> createState() => _RoomFormSheetState();
}

class _RoomFormSheetState extends State<RoomFormSheet> {
  final form = GlobalKey<FormState>();
  late final number = TextEditingController(text: widget.room?.number ?? '');
  late final category = TextEditingController(
    text: widget.room?.category ?? '',
  );
  late int? version = widget.room?.version;
  bool saving = false;
  String? error;
  bool get dirty =>
      number.text != (widget.room?.number ?? '') ||
      category.text != (widget.room?.category ?? '');
  @override
  void dispose() {
    number.dispose();
    category.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.backend.mutate(
        widget.room == null
            ? RoomCatalogAction.create
            : RoomCatalogAction.update,
        {
          'number': number.text.trim(),
          'category': category.text.trim(),
          if (version != null) 'version': version,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      String? currentCategory;
      if (widget.room != null) {
        try {
          final current = (await widget.backend.snapshot()).rooms
              .where((r) => r.number == widget.room!.number)
              .firstOrNull;
          if (current != null) {
            version = current.version;
            currentCategory = current.category;
          }
        } catch (_) {
          /* Preserve the original version and draft. */
        }
      }
      if (mounted) {
        setState(
          () => error =
              '${e.toString()}${currentCategory == null ? '' : '\nCatégorie actuelle : $currentCategory. Vérifiez avant de renvoyer.'}',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => DraftGuard(
    dirty: dirty,
    busy: saving,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: form,
        onChanged: () => setState(() {}),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.room == null
                  ? 'Créer une chambre'
                  : 'Modifier la chambre ${widget.room!.number}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
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
              controller: number,
              readOnly: widget.room != null,
              enabled: !saving,
              keyboardType: TextInputType.number,
              maxLength: 3,
              decoration: InputDecoration(
                labelText: 'Numéro de chambre',
                helperMaxLines: 3,
                helperText: widget.room == null
                    ? '100 à 999 · premier chiffre = étage'
                    : 'Le numéro reste fixe pour préserver l’historique.',
              ),
              validator: (v) =>
                  RegExp(r'^[1-9][0-9]{2}$').hasMatch(v?.trim() ?? '')
                  ? null
                  : 'Saisissez un numéro de 100 à 999.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: category,
              enabled: !saving,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Catégorie',
                hintText: 'Chambre Deluxe, Suite, Chambre standard…',
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Renseignez la catégorie.'
                  : null,
            ),
            if (widget.room == null)
              const Text(
                'La chambre sera à nettoyer. La gouvernante attribuera le nettoyage puis le validera avant sa mise à disposition.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            const SizedBox(height: 20),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: saving ? null : save,
                child: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(),
                      )
                    : Text(
                        widget.room == null
                            ? 'Créer la chambre'
                            : 'Enregistrer',
                      ),
              ),
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
