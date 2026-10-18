import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../../shared/custom/app_widgets.dart';
import '../../shared/custom/draft_guard.dart';
import '../models/room.dart';
import '../services/room_catalog_backend.dart';

class ManageRoomsScreen extends StatefulWidget {
  final RoomCatalogBackend backend;
  const ManageRoomsScreen({super.key, required this.backend});
  @override
  State<ManageRoomsScreen> createState() => _ManageRoomsScreenState();
}

class _ManageRoomsScreenState extends State<ManageRoomsScreen> {
  final query = TextEditingController();
  RoomCatalogSnapshot? data;
  bool loading = false, saving = false, archived = false;
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!saving) load();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    query.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final next = await widget.backend.snapshot();
      if (mounted) {
        setState(() {
          data = next;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit([Room? room]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => RoomFormSheet(backend: widget.backend, room: room),
    );
    if (!mounted || saved != true) return;
    showFeedback(
      context,
      room == null
          ? 'Chambre créée · nettoyage requis.'
          : 'Chambre mise à jour.',
    );
    await load();
  }

  Future<void> change(Room room, RoomCatalogAction action) async {
    if (saving) return;
    final restore = action == RoomCatalogAction.restore;
    if (!restore) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text('Archiver la chambre ${room.number} ?'),
          content: const Text(
            'Elle sera retirée du planning. Son historique sera conservé et vous pourrez la restaurer.',
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
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.backend.mutate(action, {
        'number': room.number,
        'version': room.version,
      });
      if (mounted) {
        showFeedback(
          context,
          restore
              ? 'Chambre restaurée · nettoyage requis.'
              : 'Chambre archivée.',
        );
      }
    } catch (e) {
      // Reconcile an uncertain response; never automatically repeat the action.
      await load();
      if (mounted) setState(() => error = e.toString());
      return;
    } finally {
      if (mounted) setState(() => saving = false);
    }
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final term = query.text.trim().toLowerCase();
    final rooms = (archived ? data?.archivedRooms : data?.rooms) ?? <Room>[];
    final visible = rooms
        .where(
          (r) =>
              r.number.contains(term) ||
              r.category.toLowerCase().contains(term),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des chambres'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: loading || saving ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: saving ? null : () => edit(),
        icon: const Icon(Icons.add),
        label: const Text('Créer une chambre'),
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  if (saving || (loading && data != null))
                    const LinearProgressIndicator(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Semantics(
                        liveRegion: true,
                        child: Column(
                          children: [
                            Text(
                              error!,
                              style: const TextStyle(color: AppColors.red),
                            ),
                            TextButton(
                              onPressed: loading ? null : load,
                              child: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: Text(
                                'Actives · ${data?.rooms.length ?? 0}',
                              ),
                              selected: !archived,
                              onSelected: (_) =>
                                  setState(() => archived = false),
                            ),
                            ChoiceChip(
                              label: Text(
                                'Archivées · ${data?.archivedRooms.length ?? 0}',
                              ),
                              selected: archived,
                              onSelected: (_) =>
                                  setState(() => archived = true),
                            ),
                          ],
                        ),
                        Text(
                          '${visible.length} résultat${visible.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (loading && data == null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (data != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (visible.isEmpty) {
                      return EmptyState(
                        term.isNotEmpty
                            ? 'Aucune chambre trouvée'
                            : archived
                            ? 'Aucune chambre archivée'
                            : 'Aucune chambre',
                        term.isNotEmpty
                            ? 'Modifiez ou effacez la recherche.'
                            : archived
                            ? 'Les chambres retirées du planning apparaîtront ici.'
                            : 'Créez la première chambre de l’hôtel.',
                      );
                    }
                    final room = visible[index];
                    return Card(
                      color: Colors.white,
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Chambre ${room.number}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('${room.category} · Étage ${room.floor}'),
                            Text(
                              archived ? 'Archivée' : room.statusLabel,
                              style: const TextStyle(color: AppColors.muted),
                            ),
                            if (!archived && !room.canArchive)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text(
                                  'Archivage indisponible : chambre occupée, en maintenance ou avec un agent attribué.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (!archived)
                                  TextButton.icon(
                                    onPressed: saving ? null : () => edit(room),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Modifier'),
                                  ),
                                TextButton.icon(
                                  onPressed:
                                      saving || (!archived && !room.canArchive)
                                      ? null
                                      : () => change(
                                          room,
                                          archived
                                              ? RoomCatalogAction.restore
                                              : RoomCatalogAction.archive,
                                        ),
                                  icon: Icon(
                                    archived
                                        ? Icons.unarchive_outlined
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
                    );
                  }, childCount: visible.isEmpty ? 1 : visible.length),
                ),
              ),
          ],
        ),
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
