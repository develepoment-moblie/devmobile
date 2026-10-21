import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/lost_item_dialogs.dart';
import '../custom/roomcard.dart';
import '../custom/text_prompt_dialog.dart';
import '../models/hotel_data.dart';
import '../models/lost_item.dart';
import 'lost_items_screen.dart';

// One found item: photo, details, full history and the supervisor's actions
// (prévenir le client, remettre, archiver).
class LostItemScreen extends StatefulWidget {
  final HotelData data;
  final String itemId;
  const LostItemScreen({super.key, required this.data, required this.itemId});
  @override
  State<LostItemScreen> createState() => _LostItemScreenState();
}

class _LostItemScreenState extends State<LostItemScreen> {
  Future<Uint8List>? _photo;
  bool _busy = false;
  String? _error;

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

  Future<void> _dialog(Widget dialog, String done) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => dialog,
    );
    if (mounted && saved == true) showFeedback(context, done);
  }

  Future<void> _archive(LostItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archiver cet objet ?'),
        content: const Text(
          'Il ne pourra plus être remis depuis l’application. Son historique est conservé.',
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
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.data.archiveLostItem(item);
      if (mounted) showFeedback(context, 'Objet archivé');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static (IconData, String) _step(LostItemEvent e) => switch (e.kind) {
    LostStatus.found => (Icons.search, 'Trouvé par ${e.actorName}'),
    LostStatus.notified => (
      Icons.campaign_outlined,
      'Client prévenu · ${e.channel?.label ?? 'canal inconnu'} · ${e.actorName}',
    ),
    LostStatus.returned => (Icons.handshake_outlined, 'Remis · ${e.actorName}'),
    LostStatus.archived => (
      Icons.inventory_2_outlined,
      'Archivé · ${e.actorName}',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final item = data.lostItems.where((i) => i.id == widget.itemId).firstOrNull;
    if (item == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Objet trouvé')),
        body: const Padding(
          padding: EdgeInsets.all(18),
          child: EmptyState(
            'Objet indisponible',
            'Cet objet n’est plus accessible. Revenez à la liste.',
          ),
        ),
      );
    }
    if (item.photoId != null) _photo ??= data.lostItemPhoto(item);
    final (color, background) = lostTone(item.status);
    final manage = data.isSupervisor && item.status.kept;
    return Scaffold(
      appBar: AppBar(title: Text('Objet trouvé · ${item.roomNumber}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: FutureBuilder(
                future: _photo,
                builder: (context, snap) => snap.hasData
                    ? Image.memory(
                        snap.data!,
                        height: 220,
                        fit: BoxFit.cover,
                        semanticLabel: 'Photo de l’objet',
                      )
                    : SizedBox(
                        height: 120,
                        child: Center(
                          child: snap.hasError
                              ? Text('${snap.error}')
                              : const CircularProgressIndicator(),
                        ),
                      ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            item.description,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              StatusBadge(
                item.status.label,
                color: color,
                background: background,
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final (label, value) in [
            ('Chambre', item.roomNumber),
            ('Trouvé le', lostDate(item.foundAt)),
            ('Trouvé par', item.foundByName),
            if (item.returnedTo != null) ('Rendu à', item.returnedTo!),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      label,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.red)),
          ],
          if (manage) ...[
            const SizedBox(height: 16),
            NovaButton(
              item.contacts.isEmpty
                  ? 'Prévenir le client'
                  : 'Nouvelle tentative de contact',
              onPressed: _busy
                  ? null
                  : () => _dialog(
                      NotifyOwnerDialog(data: data, item: item),
                      'Tentative de contact enregistrée',
                    ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _dialog(
                      TextPromptDialog(
                        title: 'Rendre l’objet',
                        label: 'Rendu à',
                        hint: 'M. Martin, chambre 305…',
                        message: item.description,
                        action: 'Confirmer la restitution',
                        maxLength: 120,
                        save: (to) => data.returnLostItem(item, to),
                      ),
                      'Objet restitué',
                    ),
              icon: const Icon(Icons.handshake_outlined),
              label: const Text('Rendre'),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _busy ? null : () => _archive(item),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Archiver'),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Historique',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (item.events.isEmpty)
            const Text(
              'Aucun historique enregistré.',
              style: TextStyle(color: AppColors.muted),
            ),
          for (final e in item.events.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_step(e).$1, size: 18, color: lostTone(e.kind).$1),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _step(e).$2,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          lostDate(e.at),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        if (e.message != null &&
                            e.kind != LostStatus.found) ...[
                          const SizedBox(height: 4),
                          Text(
                            e.message!,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
