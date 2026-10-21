import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/busy_action.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/quantity_lines_dialog.dart';
import '../custom/roomcard.dart';
import '../custom/text_prompt_dialog.dart';
import '../models/hotel_data.dart';
import '../models/inventory.dart';
import '../models/supply.dart';

(Color, Color) requestTone(RequestStatus s) => switch (s) {
  RequestStatus.requested => (AppColors.orange, AppColors.orangeLight),
  RequestStatus.approved ||
  RequestStatus.prepared => (AppColors.goldDeep, const Color(0xFFF6EEDC)),
  RequestStatus.delivered => (AppColors.green, AppColors.greenLight),
  RequestStatus.refused => (AppColors.red, AppColors.redLight),
};

// "Mes demandes" for an agent (create, follow), "Demandes de fournitures"
// for the supervisor (approve, prepare, deliver, refuse).
class SupplyRequestsScreen extends StatefulWidget {
  final HotelData data;
  const SupplyRequestsScreen({super.key, required this.data});
  @override
  State<SupplyRequestsScreen> createState() => _SupplyRequestsScreenState();
}

class _SupplyRequestsScreenState extends State<SupplyRequestsScreen>
    with ListenTo, BusyAction {
  @override
  Listenable get listenable => widget.data;
  bool done = false;

  HotelData get data => widget.data;

  void _create() {
    final items = data.roomSupplies;
    openDialog(
      QuantityLinesDialog(
        title: 'Demander des fournitures',
        action: 'Envoyer la demande',
        message: 'La gouvernante prépare votre demande à la lingerie.',
        noteLabel: 'Note (facultatif)',
        lines: [
          for (final s in items)
            QuantityLine(
              s.id,
              s.name,
              detail: '${supplyTypeLabels[s.category]} · ${s.unit}',
              max: 500,
            ),
        ],
        save: (q, note) => data.requestSupplies({
          for (final s in items)
            if (q[s.id] != null) s: q[s.id]!,
        }, note: note),
      ),
      'Demande envoyée à la gouvernante',
    );
  }

  void _approve(SupplyRequest r) => openDialog(
    QuantityLinesDialog(
      title: 'Approuver la demande',
      action: 'Approuver',
      message: 'Ajustez les quantités accordées si besoin (0 pour retirer).',
      keepZero: true,
      lines: [
        for (final l in r.lines)
          QuantityLine(
            l.supplyId,
            l.supplyName,
            detail:
                'Demandé : ${l.requested} · en stock : ${l.available}${l.available < l.requested ? ' · stock insuffisant' : ''}',
            initial: l.requested,
            max: l.requested,
          ),
      ],
      save: (q, _) => data.approveRequest(r, q),
    ),
    'Demande approuvée · l’agent est prévenu',
  );

  void _refuse(SupplyRequest r) => openDialog(
    TextPromptDialog(
      title: 'Refuser la demande',
      label: 'Raison',
      hint: 'Rupture, commande en cours…',
      action: 'Refuser',
      destructive: true,
      maxLength: 200,
      save: (reason) => data.refuseRequest(r, reason),
    ),
    'Demande refusée · l’agent est prévenu',
  );

  List<Widget> _actions(SupplyRequest r) {
    if (!data.isSupervisor || !r.status.open) return const [];
    return [
      switch (r.status) {
        RequestStatus.requested => FilledButton(
          onPressed: busy ? null : () => _approve(r),
          child: const Text('Approuver'),
        ),
        RequestStatus.approved => FilledButton(
          onPressed: busy
              ? null
              : () => run(
                  () => data.prepareRequest(r),
                  'Demande préparée · l’agent est prévenu',
                ),
          child: const Text('Marquer préparée'),
        ),
        _ => FilledButton(
          onPressed: busy || r.short
              ? null
              : () => run(
                  () => data.deliverRequest(r),
                  'Demande livrée · stock mis à jour',
                ),
          child: const Text('Marquer livrée'),
        ),
      },
      TextButton(
        onPressed: busy ? null : () => _refuse(r),
        child: const Text('Refuser'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final all = data.requests;
    final shown = [
      for (final r in all)
        if (r.status.open != done) r,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          data.isSupervisor ? 'Demandes de fournitures' : 'Mes demandes',
        ),
      ),
      floatingActionButton: data.isSupervisor
          ? null
          : FloatingActionButton.extended(
              onPressed: busy ? null : _create,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Nouvelle demande'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 96),
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(
                  'En cours · ${all.where((r) => r.status.open).length}',
                ),
                selected: !done,
                onSelected: (_) => setState(() => done = false),
              ),
              ChoiceChip(
                label: Text(
                  'Terminées · ${all.where((r) => !r.status.open).length}',
                ),
                selected: done,
                onSelected: (_) => setState(() => done = true),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            EmptyState(
              done ? 'Aucune demande terminée' : 'Aucune demande en cours',
              data.isSupervisor
                  ? 'Les demandes des agents apparaîtront ici.'
                  : 'Demandez du linge ou des produits à la gouvernante.',
            ),
          for (final (i, r) in shown.indexed)
            FadeSlideIn(
              key: ValueKey('$done-${r.id}'),
              index: i,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            data.isSupervisor
                                ? r.agentName
                                : 'Demande du ${shortDate(r.createdAt)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        StatusBadge(
                          r.status.label,
                          color: requestTone(r.status).$1,
                          background: requestTone(r.status).$2,
                        ),
                      ],
                    ),
                    if (data.isSupervisor)
                      Text(
                        shortDate(r.createdAt),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 8),
                    for (final l in r.lines)
                      Text(
                        r.status == RequestStatus.requested ||
                                l.approved == l.requested
                            ? '${l.supplyName} × ${l.requested}'
                            : '${l.supplyName} × ${l.approved} (demandé : ${l.requested})',
                        style: TextStyle(
                          color: r.status.open && l.approved > 0 && l.short
                              ? AppColors.red
                              : AppColors.ink,
                        ),
                      ),
                    if (r.note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '« ${r.note} »',
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ),
                    if (r.status.open && r.short)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: StatusBadge(
                          'Stock insuffisant',
                          color: AppColors.red,
                          background: AppColors.redLight,
                        ),
                      ),
                    if (r.refusalReason != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Refusée : ${r.refusalReason}',
                          style: const TextStyle(color: AppColors.red),
                        ),
                      ),
                    if (r.processedByName != null && !r.status.open)
                      Text(
                        '${r.status.label} par ${r.processedByName}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    if (_actions(r) case final actions when actions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(spacing: 8, children: actions),
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
