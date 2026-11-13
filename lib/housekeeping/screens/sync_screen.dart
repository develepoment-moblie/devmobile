import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/busy_action.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/sync_badge.dart';
import '../services/housekeeping_sync.dart';
import '../services/server_discovery.dart';

// "Synchronisation" (supervisor and Manager): the servers found on the Wi-Fi
// (one tap to use one), the hotel server's address, the actions waiting to
// be sent, the last sync and the conflicts.
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

  /// Servers found on the Wi-Fi while the screen is open, by id.
  final found = <String, FoundServer>{};
  StreamSubscription<FoundServer>? _listening, _scan;
  Timer? _searching;

  /// Listened long enough to say nothing was found.
  bool searched = false;

  /// The scan of the network is running.
  bool scanning = false;

  @override
  Listenable get listenable => widget.sync;

  @override
  void initState() {
    super.initState();
    final discovery = widget.sync.discovery;
    widget.sync
        .refresh()
        .then((view) {
          if (mounted && address.text.isEmpty && view.server != null) {
            address.text = '${view.server!.host}:${view.server!.port}';
          }
        }, onError: (Object e) => setState(() => error = e.toString()))
        // The scan tries the saved server's port too: read it first.
        .whenComplete(() {
          if (mounted && discovery != null) _search();
        });
    if (discovery != null) _listening = discovery.watch().listen(_heard);
  }

  void _heard(FoundServer server) {
    if (mounted && found[server.id] != server) {
      setState(() => found[server.id] = server);
    }
  }

  /// Scans the network (the announcements are listened to all along).
  void _search() {
    _scan?.cancel();
    _searching?.cancel();
    setState(() {
      scanning = true;
      searched = false;
    });
    void done() {
      if (mounted) setState(() => scanning = false);
    }

    _scan = widget.sync.scanNetwork().listen(
      _heard,
      onDone: done,
      onError: (Object _) => done(),
    );
    // The server announces itself every 2 seconds.
    _searching = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => searched = true);
    });
  }

  @override
  void dispose() {
    _listening?.cancel();
    _scan?.cancel();
    _searching?.cancel();
    address.dispose();
    super.dispose();
  }

  Future<void> _test() => run(() async {
    setState(() => check = null);
    final message = await widget.sync.testConnection(address.text);
    if (mounted) setState(() => check = message);
  }, 'Connexion réussie');

  Future<void> _use(FoundServer server) async {
    // A server this phone never synced with brings the hotel's data.
    if (widget.sync.joins(server) &&
        !await confirm(
          'Rejoindre ce serveur ?',
          'Les données « ménage » de ce téléphone seront remplacées par celles de l’hôtel enregistrées sur le serveur, s’il en a une copie. Une sauvegarde est faite avant.',
          'Rejoindre',
        )) {
      return;
    }
    await run(() async {
      setState(() => check = null);
      await widget.sync.useFoundServer(server);
      if (mounted) address.text = server.hostPort;
    }, 'Serveur enregistré');
  }

  @override
  Widget build(BuildContext context) {
    final sync = widget.sync;
    final view = sync.overview;
    final configured = view?.server != null;
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
          if (sync.discovery != null) ...[
            const _Heading(
              'Serveurs trouvés sur le Wi-Fi',
              'Le téléphone cherche le serveur de l’hôtel sur ce réseau.',
            ),
            if (found.isEmpty)
              _Line(
                Icons.wifi_find,
                scanning || !searched
                    ? 'Recherche d’un serveur sur le Wi-Fi…'
                    : 'Aucun serveur trouvé. Saisissez l’adresse ci-dessous.',
                AppColors.muted,
              ),
            for (final server in found.values)
              _FoundCard(
                key: ValueKey(server.id),
                server: server,
                inUse:
                    view?.server == server.address &&
                    view?.serverId == server.id,
                onUse: busy ? null : () => _use(server),
              ),
            if (!scanning && searched)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: busy ? null : _search,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Rechercher de nouveau'),
                ),
              ),
            const SizedBox(height: 14),
          ],
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
                              'Les actions restent sur ce téléphone et seront envoyées quand un serveur sera de nouveau enregistré. Le téléphone ne se reconnectera plus tout seul.',
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
            const _Heading(
              'Résolu automatiquement',
              'Quand deux téléphones changent la même chose, l’ordre d’arrivée au serveur décide : l’action en retard est appliquée sur la dernière version, ou annulée sur tous les téléphones si elle n’est plus possible. Rien à faire.',
            ),
            const SizedBox(height: 4),
            if (view.conflicts.isEmpty)
              const EmptyState(
                'Aucun conflit',
                'Les conflits résolus apparaîtront ici, sur tous les téléphones.',
              ),
            for (final (i, c) in view.conflicts.indexed)
              FadeSlideIn(
                key: ValueKey(c.mutationId),
                index: i,
                child: _LogCard(entry: c),
              ),
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

class _FoundCard extends StatelessWidget {
  final FoundServer server;
  final bool inUse;
  final VoidCallback? onUse;
  const _FoundCard({
    super.key,
    required this.server,
    required this.inUse,
    required this.onUse,
  });
  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    elevation: 0,
    child: ListTile(
      leading: const Icon(Icons.dns_outlined, color: AppColors.muted),
      title: Text(server.name),
      subtitle: Text(server.hostPort),
      trailing: inUse
          ? const Text(
              'Utilisé',
              style: TextStyle(
                color: AppColors.green,
                fontWeight: FontWeight.w600,
              ),
            )
          : Semantics(
              label: 'Utiliser le serveur ${server.name}',
              excludeSemantics: true,
              button: true,
              child: TextButton(
                onPressed: onUse,
                child: const Text('Utiliser'),
              ),
            ),
    ),
  );
}

class _LogCard extends StatelessWidget {
  final SyncConflict entry;
  const _LogCard({required this.entry});
  @override
  Widget build(BuildContext context) {
    final who = [
      entry.actorName ?? 'Auteur inconnu',
      if (entry.own) 'ce téléphone',
    ].join(', ');
    return Card(
      color: Colors.white,
      elevation: 0,
      child: ListTile(
        leading: Icon(
          entry.merged ? Icons.merge_type : Icons.block,
          color: entry.merged ? AppColors.green : AppColors.orange,
        ),
        title: Text(entry.label),
        subtitle: Text(
          '${entry.merged ? 'Fusionnée' : 'Annulée'} · $who · ${shortDate(entry.appliedAt)}\n${entry.message}',
        ),
        isThreeLine: true,
      ),
    );
  }
}
