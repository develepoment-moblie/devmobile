import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/busy_action.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/quantity_lines_dialog.dart';
import '../custom/roomcard.dart';
import '../models/hotel_data.dart';
import '../models/inventory.dart';
import '../models/room.dart';
import '../models/supply.dart';

(Color, Color) minibarTone(MinibarStatus s) => switch (s) {
  MinibarStatus.pending => (AppColors.orange, AppColors.orangeLight),
  MinibarStatus.billed => (AppColors.green, AppColors.greenLight),
  MinibarStatus.cancelled => (AppColors.gray, AppColors.grayLight),
};

// A room's minibar: record consumptions, correct them before billing,
// restock, and for the supervisor "Valider et facturer" (sent to billing
// once) or a compensating entry after billing.
class MinibarRoomScreen extends StatefulWidget {
  final HotelData data;
  final Room room;
  const MinibarRoomScreen({super.key, required this.data, required this.room});
  @override
  State<MinibarRoomScreen> createState() => _MinibarRoomScreenState();
}

class _MinibarRoomScreenState extends State<MinibarRoomScreen>
    with ListenTo, BusyAction {
  @override
  Listenable get listenable => widget.data;
  HotelData get data => widget.data;
  Room get room => widget.room;

  List<QuantityLine> _items({bool stock = false}) => [
    for (final s in data.minibarItems)
      QuantityLine(
        s.id,
        s.name,
        detail: stock
            ? '${s.quantity} ${s.unit} en réserve'
            : euros(s.priceCents ?? 0),
        max: stock ? s.quantity.clamp(0, 50) : 50,
      ),
  ];

  Map<Supply, int> _picked(Map<String, int> q) => {
    for (final s in data.minibarItems)
      if (q[s.id] != null) s: q[s.id]!,
  };

  void _record() => openDialog(
    QuantityLinesDialog(
      title: 'Consommations · ${room.number}',
      action: 'Enregistrer',
      message:
          'Elles restent en attente jusqu’à la validation de la gouvernante.',
      lines: _items(),
      save: (q, _) async {
        for (final e in _picked(q).entries) {
          await data.recordMinibar(room, e.key, e.value);
        }
      },
    ),
    'Consommation enregistrée',
  );

  void _restock() => openDialog(
    QuantityLinesDialog(
      title: 'Réapprovisionner le minibar',
      action: 'Réapprovisionner',
      message: 'Les articles sont pris dans la réserve.',
      lines: _items(stock: true),
      save: (q, _) => data.restockMinibar(room, _picked(q)),
    ),
    'Minibar réapprovisionné',
  );

  void _quantity(MinibarEntry e, {required bool billed}) => openDialog(
    QuantityLinesDialog(
      title: billed ? 'Corriger la facture' : 'Corriger la quantité',
      action: billed ? 'Enregistrer la correction' : 'Corriger',
      message: billed
          ? 'Déjà facturé : une écriture de correction sera envoyée à la facturation.'
          : '0 annule la consommation.',
      keepZero: true,
      lines: [
        QuantityLine(
          e.id,
          e.label,
          detail: euros(e.unitPriceCents),
          initial: billed ? data.billedQuantity(e) : e.quantity,
          max: 50,
        ),
      ],
      save: (q, _) => billed
          ? data.compensateMinibar(e, q[e.id]!)
          : data.correctMinibar(e, q[e.id]!),
    ),
    billed ? 'Correction en attente de facturation' : 'Consommation corrigée',
  );

  @override
  Widget build(BuildContext context) {
    final entries = data.minibarOf(room.number);
    final pending = [
      for (final e in entries)
        if (e.status == MinibarStatus.pending) e,
    ];
    final postable = [
      for (final e in pending)
        if (!e.stayChanged) e,
    ];
    final total = postable.fold(0, (sum, e) => sum + e.amountCents);
    final canWork = data.isSupervisor || data.canClean(room);
    return Scaffold(
      appBar: AppBar(title: Text('Minibar · ${room.number}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (canWork)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : _record,
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une consommation'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : _restock,
                  icon: const Icon(Icons.inventory_outlined),
                  label: const Text('Réapprovisionner'),
                ),
              ],
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
            ),
          if (data.isSupervisor && pending.isNotEmpty) ...[
            const SizedBox(height: 16),
            if (postable.isNotEmpty)
              NovaButton(
                'Valider et facturer · ${euros(total)}',
                onPressed: busy
                    ? null
                    : () => run(
                        () => data.postMinibar(room.number, postable),
                        'Envoyé à la facturation',
                      ),
              ),
            if (postable.length < pending.length)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Le client de certaines consommations est parti : à transmettre à la réception.',
                  style: TextStyle(color: AppColors.red, fontSize: 12.5),
                ),
              ),
          ],
          const SizedBox(height: 18),
          if (entries.isEmpty)
            const EmptyState(
              'Aucune consommation',
              'Les consommations du minibar de cette chambre apparaîtront ici.',
            ),
          for (final (i, e) in entries.indexed)
            FadeSlideIn(
              key: ValueKey(e.id),
              index: i,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.isCorrection
                                ? 'Correction · ${e.label} ${e.quantity > 0 ? '+' : ''}${e.quantity}'
                                : '${e.label} × ${e.quantity}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          euros(e.amountCents),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        StatusBadge(
                          e.status.label,
                          color: minibarTone(e.status).$1,
                          background: minibarTone(e.status).$2,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${e.recordedByName} · ${shortDate(e.recordedAt)}',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (e.status == MinibarStatus.pending &&
                        (data.isSupervisor ||
                            e.recordedBy == data.currentUserId))
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => _quantity(e, billed: false),
                        child: const Text('Corriger'),
                      ),
                    if (e.status == MinibarStatus.billed &&
                        !e.isCorrection &&
                        data.isSupervisor)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => _quantity(e, billed: true),
                        child: const Text('Corriger la facture'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// The supervisor's minibar view: rooms with consumptions to validate.
class MinibarBillingScreen extends StatelessWidget {
  final HotelData data;
  const MinibarBillingScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: data,
    builder: (context, _) {
      final pending = <String, List<MinibarEntry>>{};
      for (final e in data.minibar) {
        if (e.status == MinibarStatus.pending) {
          pending.putIfAbsent(e.roomNumber, () => []).add(e);
        }
      }
      final rooms = pending.keys.toList()..sort();
      final billed = [
        for (final e in data.minibar)
          if (e.status == MinibarStatus.billed) e,
      ];
      return Scaffold(
        appBar: AppBar(title: const Text('Minibar à facturer')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
          children: [
            if (rooms.isEmpty)
              const EmptyState(
                'Rien à facturer',
                'Les consommations enregistrées par les agents apparaîtront ici.',
              ),
            for (final number in rooms)
              Card(
                color: Colors.white,
                elevation: 0,
                child: ListTile(
                  leading: const Icon(Icons.local_bar_outlined),
                  title: Text('Chambre $number'),
                  subtitle: Text(
                    '${pending[number]!.length} en attente · ${euros(pending[number]!.fold(0, (s, e) => s + e.amountCents))}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    final room = data.rooms
                        .where((r) => r.number == number)
                        .firstOrNull;
                    if (room == null) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            MinibarRoomScreen(data: data, room: room),
                      ),
                    );
                  },
                ),
              ),
            if (billed.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Déjà facturé',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final e in billed.take(30))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Chambre ${e.roomNumber} · ${e.isCorrection ? 'correction ' : ''}${e.label} ${e.isCorrection && e.quantity > 0
                        ? '+'
                        : e.isCorrection
                        ? ''
                        : '× '}${e.quantity}',
                  ),
                  subtitle: Text(
                    '${e.billedByName} · ${shortDate(e.billedAt ?? e.recordedAt)}',
                  ),
                  trailing: Text(euros(e.amountCents)),
                ),
            ],
          ],
        ),
      );
    },
  );
}
