import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../custom/busy_action.dart';
import '../custom/housekeeping_widgets.dart';
import '../models/hotel_data.dart';

// The usage log: every stock change, filtered by floor and room.
class StockLogScreen extends StatefulWidget {
  final HotelData data;
  const StockLogScreen({super.key, required this.data});
  @override
  State<StockLogScreen> createState() => _StockLogScreenState();
}

class _StockLogScreenState extends State<StockLogScreen> with ListenTo {
  @override
  Listenable get listenable => widget.data;
  int? floor;
  String? room;

  @override
  Widget build(BuildContext context) {
    final all = widget.data.movements.reversed.toList();
    final floors = {for (final m in all) ?m.floor}.toList()..sort();
    final rooms = {
      for (final m in all)
        if (m.roomNumber != null && (floor == null || m.floor == floor))
          m.roomNumber!,
    }.toList()..sort();
    final shown = [
      for (final m in all)
        if ((floor == null || m.floor == floor) &&
            (room == null || m.roomNumber == room))
          m,
    ];
    final used = <String, int>{};
    for (final m in shown) {
      if (m.reason == 'usage' || m.reason == 'minibar_restock') {
        used[m.supplyName] = (used[m.supplyName] ?? 0) + m.quantity;
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Journal du stock')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: floor,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Étage'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tous')),
                    for (final f in floors)
                      DropdownMenuItem(
                        value: f,
                        child: Text(widget.data.floorName(f)),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    floor = v;
                    room = null;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('room-$floor'),
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
            ],
          ),
          if (used.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Utilisé dans les chambres',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            for (final e in used.entries) Text('${e.key} : ${e.value}'),
          ],
          const SizedBox(height: 14),
          if (shown.isEmpty)
            const EmptyState(
              'Aucun mouvement',
              'Les utilisations, envois en blanchisserie et livraisons apparaîtront ici.',
            ),
          for (final m in shown)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                m.delta > 0
                    ? Icons.add_circle_outline
                    : m.delta < 0
                    ? Icons.remove_circle_outline
                    : Icons.report_gmailerrorred_outlined,
                color: m.delta > 0
                    ? AppColors.green
                    : m.delta < 0
                    ? AppColors.primary
                    : AppColors.red,
              ),
              title: Text('${m.supplyName} · ${m.reasonLabel}'),
              subtitle: Text(
                [
                  if (m.roomNumber != null) 'Chambre ${m.roomNumber}',
                  m.actorName,
                  shortDate(m.at),
                ].join(' · '),
              ),
              trailing: Text(
                m.delta == 0
                    ? '${m.quantity}'
                    : '${m.delta > 0 ? '+' : '−'}${m.delta.abs()}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}
