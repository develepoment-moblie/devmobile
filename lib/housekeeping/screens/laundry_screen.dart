import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/busy_action.dart';
import '../custom/draft_guard.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/quantity_lines_dialog.dart';
import '../custom/roomcard.dart';
import '../models/hotel_data.dart';
import '../models/inventory.dart';

// "Linge en blanchisserie" (supervisor): send linen, then record what came
// back, damaged or lost. Sending takes it out of stock; only what is
// received goes back in.
class LaundryScreen extends StatefulWidget {
  final HotelData data;
  const LaundryScreen({super.key, required this.data});
  @override
  State<LaundryScreen> createState() => _LaundryScreenState();
}

class _LaundryScreenState extends State<LaundryScreen>
    with ListenTo, BusyAction {
  @override
  Listenable get listenable => widget.data;

  void _send() {
    final linen = widget.data.suppliesOf('linge');
    openDialog(
      QuantityLinesDialog(
        title: 'Envoyer du linge',
        action: 'Envoyer',
        message: 'Le linge envoyé sort du stock jusqu’à son retour.',
        noteLabel: 'Note (facultatif)',
        lines: [
          for (final s in linen)
            QuantityLine(
              s.id,
              s.name,
              detail: '${s.quantity} ${s.unit} en stock',
              max: s.quantity,
            ),
        ],
        save: (q, note) => widget.data.sendLaundry({
          for (final s in linen)
            if (q[s.id] != null) s: q[s.id]!,
        }, note: note),
      ),
      'Linge envoyé en blanchisserie',
    );
  }

  @override
  Widget build(BuildContext context) {
    final batches = widget.data.laundry;
    final out = batches.where((b) => !b.returned).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Linge en blanchisserie')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : _send,
        icon: const Icon(Icons.local_laundry_service_outlined),
        label: const Text('Envoyer du linge'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 96),
        children: [
          Text(
            out.isEmpty
                ? 'Aucun linge en blanchisserie.'
                : '${out.length} envoi${out.length > 1 ? 's' : ''} en attente de retour · ${out.fold(0, (n, b) => n + b.sent)} pièces',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: AppColors.red)),
            ),
          const SizedBox(height: 12),
          if (batches.isEmpty)
            const EmptyState(
              'Aucun envoi',
              'Envoyez le linge sale à la blanchisserie, puis enregistrez son retour.',
            ),
          for (final (i, batch) in batches.indexed)
            FadeSlideIn(
              key: ValueKey(batch.id),
              index: i,
              child: _BatchCard(
                batch: batch,
                onReturn: busy
                    ? null
                    : () => openDialog(
                        LaundryReturnDialog(data: widget.data, batch: batch),
                        'Retour enregistré',
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BatchCard extends StatelessWidget {
  final LaundryBatch batch;
  final VoidCallback? onReturn;
  const _BatchCard({required this.batch, required this.onReturn});

  @override
  Widget build(BuildContext context) => Container(
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
                'Envoyé le ${shortDate(batch.sentAt)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            batch.returned
                ? const StatusBadge(
                    'Revenu',
                    color: AppColors.green,
                    background: AppColors.greenLight,
                  )
                : const StatusBadge(
                    'En blanchisserie',
                    color: AppColors.orange,
                    background: AppColors.orangeLight,
                  ),
          ],
        ),
        Text(
          'Par ${batch.sentByName}${batch.note == null ? '' : ' · ${batch.note}'}',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        for (final l in batch.lines)
          Text(
            batch.returned
                ? '${l.supplyName} : ${l.sent} envoyés · ${l.received} reçus'
                      '${(l.damaged ?? 0) > 0 ? ' · ${l.damaged} abîmés' : ''}'
                      '${(l.lost ?? 0) > 0 ? ' · ${l.lost} perdus' : ''}'
                : '${l.supplyName} : ${l.sent} ${l.unit}',
          ),
        if (batch.returned && batch.returnedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Retour le ${shortDate(batch.returnedAt!)} · ${batch.returnedByName}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        if (!batch.returned) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onReturn,
            icon: const Icon(Icons.assignment_return_outlined),
            label: const Text('Enregistrer le retour'),
          ),
        ],
      ],
    ),
  );
}

// Received, damaged and lost per item; each line must add up to what was
// sent. Returns true once saved.
class LaundryReturnDialog extends StatefulWidget {
  final HotelData data;
  final LaundryBatch batch;
  const LaundryReturnDialog({
    super.key,
    required this.data,
    required this.batch,
  });
  @override
  State<LaundryReturnDialog> createState() => _LaundryReturnDialogState();
}

class _LaundryReturnDialogState extends State<LaundryReturnDialog> {
  final _form = GlobalKey<FormState>();
  late final _fields = {
    for (final l in widget.batch.lines)
      l.supplyId: [
        TextEditingController(text: '${l.sent}'),
        TextEditingController(text: '0'),
        TextEditingController(text: '0'),
      ],
  };
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final list in _fields.values) {
      for (final c in list) {
        c.dispose();
      }
    }
    super.dispose();
  }

  int _n(String id, int i) => int.tryParse(_fields[id]![i].text.trim()) ?? 0;

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.data.returnLaundry(widget.batch, {
        for (final l in widget.batch.lines)
          l.supplyId: (
            received: _n(l.supplyId, 0),
            damaged: _n(l.supplyId, 1),
            lost: _n(l.supplyId, 2),
          ),
      });
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String id, int i, String label) => Expanded(
    child: TextFormField(
      key: ValueKey('$label-$id'),
      controller: _fields[id]![i],
      enabled: !_busy,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, isDense: true),
    ),
  );

  @override
  Widget build(BuildContext context) => DraftGuard(
    dirty: false,
    busy: _busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Retour de blanchisserie'),
      content: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Seul le linge reçu en bon état revient en stock. L’abîmé et le perdu sont notés dans le journal.',
              style: TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
            for (final l in widget.batch.lines) ...[
              const SizedBox(height: 14),
              Text(
                '${l.supplyName} · ${l.sent} envoyés',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _field(l.supplyId, 0, 'Reçu'),
                  const SizedBox(width: 8),
                  _field(l.supplyId, 1, 'Abîmé'),
                  const SizedBox(width: 8),
                  _field(l.supplyId, 2, 'Perdu'),
                ],
              ),
              Builder(
                builder: (context) {
                  final total =
                      _n(l.supplyId, 0) + _n(l.supplyId, 1) + _n(l.supplyId, 2);
                  return Text(
                    total == l.sent
                        ? 'Total : $total / ${l.sent}'
                        : 'Total : $total / ${l.sent} · doit faire ${l.sent}',
                    style: TextStyle(
                      fontSize: 12,
                      color: total == l.sent ? AppColors.muted : AppColors.red,
                    ),
                  );
                },
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.maybePop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Enregistrer le retour'),
        ),
      ],
    ),
  );
}
