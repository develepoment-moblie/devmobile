import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/busy_action.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/sync_badge.dart';
import '../services/housekeeping_sync.dart';

// "Synchronisation" (supervisor and Manager): the hotel server's address,
// the actions waiting to be sent, the last sync and the conflicts.
class SyncScreen extends StatefulWidget {
  final HousekeepingSync sync;
  const SyncScreen({super.key, required this.sync});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen>
    with BusyAction, ListenTo<SyncScreen> {
  final address = TextEditingController();
  String? check;

  @override
  Listenable get listenable => widget.sync;

  @override
  void initState() {
    super.initState();
    widget.sync.refresh().then((view) {
      if (mounted && address.text.isEmpty && view.server != null) {
        address.text = '${view.server!.host}:${view.server!.port}';
      }
    }, onError: (Object e) => setState(() => error = e.toString()));
  }

  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  Widget _conflict(SyncConflict c) => _ConflictCard(
    title: c.label,
    subtitle:
        '${c.actorName ?? 'Auteur inconnu'} · ${shortDate(c.appliedAt)}\n${c.message}',
    onDismiss: busy
        ? null
        : () => run(
            () => widget.sync.dismissConflict(c.mutationId),
            'Conflit retiré',
          ),
  );

  Future<void> _test() => run(() async {
    setState(() => check = null);
    final message = await widget.sync.testConnection(address.text);
    if (mounted) setState(() => check = message);
  }, 'Connexion réussie');

  @override
  Widget build(BuildContext context) {
    final sync = widget.sync;
    final view = sync.overview;
    final configured = view?.server != null;
    final own = [...?view?.conflicts.where((c) => c.own)];
    final others = [...?view?.conflicts.where((c) => !c.own)];
    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          const Text(
            'Chaque action est enregistrée d’abord sur ce téléphone, puis envoyée au serveur de l’hôtel. Le téléphone reçoit aussi ce que les autres ont fait. Sans réseau, rien n’est perdu : les actions attendent le retour du Wi-Fi.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: address,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Adresse du serveur',
              hintText: '192.168.1.20:8080',
              helperText: 'Affichée au démarrage du serveur sur l’ordinateur.',
            ),
          ),
          if (busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
            ),
          if (check != null && error == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                check!,
                style: const TextStyle(color: AppColors.green),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _test,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Tester la connexion'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NovaButton(
                  'Enregistrer',
                  onPressed: busy
                      ? null
                      : () => run(
                          () => sync.setServer(address.text),
                          'Serveur enregistré',
                        ),
                ),
              ),
            ],
          ),
          if (configured) ...[
            const SizedBox(height: 22),
            Row(
              children: [
                const Text(
                  'État',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SyncBadge(sync: sync),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Line(
              Icons.outbox_outlined,
              view!.pending == 0
                  ? 'Aucune action en attente'
                  : pendingText(view.pending),
            ),
            _Line(
              Icons.schedule,
              view.lastSyncAt == null
                  ? 'Jamais synchronisé'
                  : 'Dernière synchronisation : ${shortDate(view.lastSyncAt!)}',
            ),
            if (view.lastError != null)
              _Line(Icons.cloud_off_outlined, view.lastError!, AppColors.red),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: busy || sync.phase == SyncPhase.syncing
                        ? null
                        : () => run(() async {
                            if (!await sync.syncNow()) {
                              throw Exception(
                                sync.overview?.lastError ??
                                    'Serveur injoignable.',
                              );
                            }
                          }, 'Synchronisé'),
                    icon: const Icon(Icons.sync),
                    label: const Text('Synchroniser'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            final ok = await confirm(
                              'Arrêter la synchronisation ?',
                              'Les actions restent sur ce téléphone et seront envoyées quand un serveur sera de nouveau enregistré.',
                              'Arrêter',
                            );
                            if (ok) await sync.clearServer();
                          }, 'Synchronisation arrêtée'),
                    child: const Text('Arrêter'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              view.conflicts.isEmpty && view.rejected.isEmpty
                  ? 'Conflits'
                  : 'Conflits · ${view.conflicts.length + view.rejected.length}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (view.conflicts.isEmpty && view.rejected.isEmpty)
              const EmptyState(
                'Aucun conflit',
                'Quand deux téléphones changent la même chose, l’ordre d’arrivée au serveur décide. Une action refusée apparaîtra ici, sur tous les téléphones.',
              ),
            if (own.isNotEmpty || view.rejected.isNotEmpty) ...[
              const _Heading(
                'Vos actions refusées',
                'Retirées de ce téléphone : refaites-les si besoin.',
              ),
              for (final (i, c) in own.indexed)
                FadeSlideIn(
                  key: ValueKey(c.mutationId),
                  index: i,
                  child: _conflict(c),
                ),
              for (final r in view.rejected)
                _ConflictCard(
                  key: ValueKey(r.mutationId),
                  title: r.label,
                  subtitle:
                      'Refusée par le serveur · ${shortDate(r.appliedAt)}\n${r.error}',
                  onDismiss: busy
                      ? null
                      : () => run(
                          () => sync.dismissRejected(r.mutationId),
                          'Action retirée',
                        ),
                ),
            ],
            if (others.isNotEmpty) ...[
              const _Heading(
                'Actions d’autres téléphones refusées',
                'Arrivées au serveur après une autre modification.',
              ),
              for (final (i, c) in others.indexed)
                FadeSlideIn(
                  key: ValueKey(c.mutationId),
                  index: i,
                  child: _conflict(c),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String title, hint;
  const _Heading(this.title, this.hint);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        Text(
          hint,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Line(this.icon, this.text, [this.color = AppColors.ink]);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    ),
  );
}

class _ConflictCard extends StatelessWidget {
  final String title, subtitle;
  final VoidCallback? onDismiss;
  const _ConflictCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onDismiss,
  });
  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    elevation: 0,
    child: ListTile(
      leading: const Icon(Icons.call_split, color: AppColors.orange),
      title: Text(title),
      subtitle: Text(subtitle),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: 'Retirer « $title » de la liste',
        onPressed: onDismiss,
        icon: const Icon(Icons.close),
      ),
    ),
  );
}
