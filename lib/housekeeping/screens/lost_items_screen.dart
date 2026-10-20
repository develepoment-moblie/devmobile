import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/text_prompt_dialog.dart';
import '../models/hotel_data.dart';
import '../models/lost_item.dart';

// The supervisor's lost and found register.
class LostItemsScreen extends StatefulWidget {
  final HotelData data;
  const LostItemsScreen({super.key, required this.data});
  @override
  State<LostItemsScreen> createState() => _LostItemsScreenState();
}

class _LostItemsScreenState extends State<LostItemsScreen> {
  bool returned = false;

  @override
  void initState() {
    super.initState();
    widget.data.addListener(_changed);
  }

  @override
  void dispose() {
    widget.data.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> giveBack(LostItem item) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TextPromptDialog(
        title: 'Rendre l’objet',
        label: 'Rendu à',
        hint: 'M. Martin, chambre 305…',
        message: item.description,
        action: 'Confirmer la restitution',
        maxLength: 120,
        save: (to) => widget.data.returnLostItem(item, to),
      ),
    );
    if (mounted && saved == true) showFeedback(context, 'Objet restitué');
  }

  Future<void> photo(LostItem item) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(item.description),
      content: FutureBuilder(
        future: widget.data.lostItemPhoto(item),
        builder: (context, snap) => snap.hasData
            ? ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(snap.data!, fit: BoxFit.contain),
              )
            : snap.hasError
            ? Text('${snap.error}')
            : const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final all = widget.data.lostItems;
    final items = [
      for (final i in all)
        if (i.returned == returned) i,
    ];
    final waiting = all.where((i) => !i.returned).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Objets trouvés')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text('À rendre · $waiting'),
                selected: !returned,
                onSelected: (_) => setState(() => returned = false),
              ),
              ChoiceChip(
                label: Text('Rendus · ${all.length - waiting}'),
                selected: returned,
                onSelected: (_) => setState(() => returned = true),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            EmptyState(
              returned ? 'Aucun objet rendu' : 'Aucun objet en attente',
              returned
                  ? 'Les objets rendus à leur propriétaire apparaîtront ici.'
                  : 'Les agents enregistrent les objets trouvés depuis la fiche de la chambre.',
            ),
          for (final (i, item) in items.indexed)
            FadeSlideIn(
              key: ValueKey('$returned-${item.id}'),
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.orangeLight,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Text(
                                item.roomNumber,
                                style: const TextStyle(
                                  color: AppColors.orange,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.description,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Trouvé par ${item.foundByName} · ${_date(item.foundAt)}',
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
                        if (item.returned) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Rendu à ${item.returnedTo} · ${_date(item.returnedAt!)}',
                            style: const TextStyle(
                              color: AppColors.green,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (item.photoId != null)
                              TextButton.icon(
                                onPressed: () => photo(item),
                                icon: const Icon(Icons.image_outlined),
                                label: const Text('Photo'),
                              ),
                            if (!item.returned && widget.data.isSupervisor)
                              TextButton.icon(
                                onPressed: () => giveBack(item),
                                icon: const Icon(Icons.handshake_outlined),
                                label: const Text('Rendre'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
