import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/lost_item_dialogs.dart';
import '../custom/roomcard.dart';
import '../models/hotel_data.dart';
import '../models/lost_item.dart';
import 'lost_item_screen.dart';

(Color, Color) lostTone(LostStatus status) => switch (status) {
  LostStatus.found => (AppColors.orange, AppColors.orangeLight),
  LostStatus.notified => (AppColors.goldDeep, const Color(0xFFF6EEDC)),
  LostStatus.returned => (AppColors.green, AppColors.greenLight),
  LostStatus.archived => (AppColors.gray, AppColors.grayLight),
};

String lostDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Periods of the date filter, in days (null: every date).
const _periods = <int?, String>{
  null: 'Toutes les dates',
  1: 'Aujourd’hui',
  7: '7 derniers jours',
  30: '30 derniers jours',
};

// The lost and found register: search, filters by status, room and date.
class LostItemsScreen extends StatefulWidget {
  final HotelData data;
  const LostItemsScreen({super.key, required this.data});
  @override
  State<LostItemsScreen> createState() => _LostItemsScreenState();
}

class _LostItemsScreenState extends State<LostItemsScreen> {
  final _search = TextEditingController();
  LostStatus? status;
  String? room;
  int? period;

  @override
  void initState() {
    super.initState();
    widget.data.addListener(_changed);
  }

  @override
  void dispose() {
    widget.data.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool _matches(LostItem item, DateTime now) {
    final query = _search.text.trim().toLowerCase();
    if (query.isNotEmpty &&
        !item.description.toLowerCase().contains(query) &&
        !item.foundByName.toLowerCase().contains(query)) {
      return false;
    }
    if (room != null && item.roomNumber != room) return false;
    if (period != null) {
      final today = DateTime(now.year, now.month, now.day);
      final since = today.subtract(Duration(days: period! - 1));
      if (item.foundAt.isBefore(since)) return false;
    }
    return true;
  }

  Future<void> _settings() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ArchiveDelayDialog(data: widget.data),
    );
    if (mounted && saved == true) {
      showFeedback(
        context,
        'Archivage après ${widget.data.lostArchiveDays} jours',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final now = DateTime.now();
    final matching = [
      for (final i in data.lostItems)
        if (_matches(i, now)) i,
    ];
    final items = [
      for (final i in matching)
        if (status == null || i.status == status) i,
    ];
    final rooms = {for (final i in data.lostItems) i.roomNumber}.toList()
      ..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Objets trouvés'),
        actions: [
          if (data.isSupervisor)
            IconButton(
              tooltip: 'Archivage automatique',
              onPressed: _settings,
              icon: const Icon(Icons.auto_delete_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Rechercher un objet ou une personne',
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer la recherche',
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: room,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Chambre'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Toutes')),
                    for (final r in rooms)
                      DropdownMenuItem(value: r, child: Text(r)),
                  ],
                  onChanged: (v) => setState(() => room = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: period,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Trouvé'),
                  items: [
                    for (final e in _periods.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => period = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text('Tous · ${matching.length}'),
                selected: status == null,
                onSelected: (_) => setState(() => status = null),
              ),
              for (final s in LostStatus.values)
                ChoiceChip(
                  label: Text(
                    '${s.label} · ${matching.where((i) => i.status == s).length}',
                  ),
                  selected: status == s,
                  onSelected: (_) => setState(() => status = s),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            EmptyState(
              data.lostItems.isEmpty
                  ? 'Aucun objet trouvé'
                  : 'Aucun objet ne correspond',
              data.lostItems.isEmpty
                  ? 'Les agents enregistrent les objets trouvés depuis la fiche de la chambre.'
                  : 'Modifiez la recherche ou les filtres.',
            ),
          for (final (i, item) in items.indexed)
            FadeSlideIn(
              key: ValueKey('${status?.name}-${item.id}'),
              index: i,
              child: LostItemCard(
                item: item,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => LostItemScreen(data: data, itemId: item.id),
                  ),
                ),
              ),
            ),
          if (data.isSupervisor)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Les objets non réclamés sont archivés après ${data.lostArchiveDays} jours.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class LostItemCard extends StatelessWidget {
  final LostItem item;
  final VoidCallback onTap;
  const LostItemCard({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (color, background) = lostTone(item.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    item.roomNumber,
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Trouvé par ${item.foundByName} · ${lostDate(item.foundAt)}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      if (item.returned && item.returnedTo != null)
                        Text(
                          'Rendu à ${item.returnedTo}',
                          style: const TextStyle(
                            color: AppColors.green,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          StatusBadge(
                            item.status.label,
                            color: color,
                            background: background,
                          ),
                          if (item.photoId != null) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.image_outlined,
                              size: 16,
                              color: AppColors.muted,
                              semanticLabel: 'Avec photo',
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
