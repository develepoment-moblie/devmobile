import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/add_rooms_sheet.dart';
import '../custom/catalog_widgets.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/room_qr.dart';
import '../custom/roomcard.dart';
import '../custom/text_prompt_dialog.dart';
import '../models/catalog_data.dart';
import '../models/room.dart';
import '../services/room_catalog_backend.dart';
import 'manage_rooms_screen.dart';

// One floor: its rooms as a grid, with status summary and room actions.
class FloorScreen extends StatefulWidget {
  final CatalogData catalog;
  final int floor;
  const FloorScreen({super.key, required this.catalog, required this.floor});
  @override
  State<FloorScreen> createState() => _FloorScreenState();
}

class _FloorScreenState extends State<FloorScreen> {
  CatalogData get catalog => widget.catalog;

  @override
  void initState() {
    super.initState();
    catalog.addListener(_changed);
  }

  @override
  void dispose() {
    catalog.removeListener(_changed);
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
      builder: (_) => AddRoomsSheet(catalog: catalog, floor: widget.floor),
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

  Future<void> rename() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TextPromptDialog(
        title: 'Renommer l’étage',
        label: 'Nom de l’étage',
        hint: 'Étage ${widget.floor} · Suites',
        action: 'Enregistrer',
        maxLength: 60,
        save: (name) => catalog.change(RoomCatalogAction.renameFloor, {
          'floor': widget.floor,
          'name': name,
          'version': catalog.snapshot?.floorVersions[widget.floor],
        }),
      ),
    );
    if (mounted && saved == true) showFeedback(context, 'Étage renommé');
  }

  @override
  Widget build(BuildContext context) {
    final rooms = catalog.roomsOn(widget.floor);
    final counts = RoomCounts.of(rooms);
    return Scaffold(
      appBar: AppBar(
        title: Text(catalog.floorName(widget.floor)),
        actions: [
          IconButton(
            tooltip: 'Renommer l’étage',
            onPressed: rename,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addRooms,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter des chambres'),
      ),
      body: RefreshIndicator(
        onRefresh: catalog.load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              sliver: SliverToBoxAdapter(
                child: FadeSlideIn(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppShadows.soft,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            AnimatedCount(
                              counts.total,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Text(
                                counts.total == 1 ? 'chambre' : 'chambres',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        StatusBar(counts),
                        const SizedBox(height: 10),
                        StatusLegend(counts),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (rooms.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  'Aucune chambre à cet étage',
                  'Ajoutez les chambres de l’étage, une par une ou par plage.',
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 150,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: .95,
                ),
                itemCount: rooms.length,
                itemBuilder: (context, i) => FadeSlideIn(
                  index: i,
                  child: RoomTile(
                    room: rooms[i],
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) =>
                          RoomSheet(catalog: catalog, number: rooms[i].number),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// A room's status, recent history and the Manager's actions.
class RoomSheet extends StatefulWidget {
  final CatalogData catalog;
  final String number;
  const RoomSheet({super.key, required this.catalog, required this.number});
  @override
  State<RoomSheet> createState() => _RoomSheetState();
}

class _RoomSheetState extends State<RoomSheet> {
  bool busy = false;
  String? error;

  Room? get room =>
      widget.catalog.rooms.where((r) => r.number == widget.number).firstOrNull;

  Future<void> editCategory(Room room) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) =>
          RoomFormSheet(backend: widget.catalog.backend, room: room),
    );
    await widget.catalog.load();
    if (mounted && saved == true) setState(() {});
  }

  Future<void> archive(Room room) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archiver la chambre ${room.number} ?'),
        content: const Text(
          'Elle sera retirée du planning. Son historique est conservé et vous pourrez la restaurer.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archiver'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.catalog.change(RoomCatalogAction.archive, {
        'number': room.number,
        'version': room.version,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = room;
    if (r == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: EmptyState('Chambre indisponible', 'Elle a été archivée.'),
      );
    }
    final (color, background) = roomTone(r, cleaning: false);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  r.number,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chambre ${r.number}',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${r.category} · ${widget.catalog.floorName(r.floor)}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge(r.statusLabel, color: color, background: background),
              if (r.needsCleaning)
                StatusBadge(
                  r.cleaningLabel,
                  color: color,
                  background: background,
                ),
              StatusBadge(
                '${r.tasks.length} tâches',
                color: AppColors.gray,
                background: AppColors.grayLight,
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: AppColors.red)),
          ],
          const SizedBox(height: 18),
          const Text(
            'Derniers événements',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final entry in r.history.reversed.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                entry,
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: busy ? null : () => editCategory(r),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Modifier la catégorie'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  RoomQrDialog(number: r.number, category: r.category),
            ),
            icon: const Icon(Icons.qr_code_2),
            label: const Text('QR code de la porte'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy || !r.canArchive ? null : () => archive(r),
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Archiver'),
          ),
          if (!r.canArchive)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Archivage indisponible : chambre occupée, en maintenance ou avec un nettoyage en cours.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}
