import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/busy_action.dart';
import '../custom/housekeeping_widgets.dart';
import '../services/housekeeping_backup.dart';

/// Sends a backup file out of the phone (Drive, e-mail, Fichiers).
typedef ShareBackup = Future<void> Function(BackupInfo backup);

/// Lets the user choose a backup file; null when cancelled.
typedef PickBackup = Future<Uint8List?> Function();

Future<void> shareWithAndroid(BackupInfo backup) => SharePlus.instance.share(
  ShareParams(
    files: [XFile(backup.path, mimeType: 'application/gzip')],
    subject: 'Sauvegarde Nova Paris · ménage',
    text: 'Sauvegarde du module ménage du ${shortDate(backup.createdAt)}.',
  ),
);

Future<Uint8List?> pickWithAndroid() async {
  final files = await FilePicker.pickFiles(
    dialogTitle: 'Choisir une sauvegarde',
  );
  return files.isEmpty ? null : files.first.readAsBytes();
}

String sizeText(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).ceil()} Ko'
    : '${(bytes / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} Mo';

// "Sauvegardes": back up the housekeeping data now, share a backup, restore
// one (Manager or admin). Automatic backups are made once a day.
class BackupScreen extends StatefulWidget {
  final HousekeepingBackup backup;
  final ShareBackup share;
  final PickBackup pick;
  const BackupScreen({
    super.key,
    required this.backup,
    this.share = shareWithAndroid,
    this.pick = pickWithAndroid,
  });
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> with BusyAction {
  List<BackupInfo>? backups;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final found = await widget.backup.list();
      if (mounted) setState(() => backups = found);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _restore(Future<Uint8List?> Function() source) async {
    final ok = await confirm(
      'Restaurer cette sauvegarde ?',
      'Toutes les données du ménage (chambres, nettoyages, stock, signalements…) '
          'seront remplacées. Une sauvegarde de l’état actuel est faite avant.',
      'Restaurer',
    );
    if (!ok) return;
    await run(() async {
      final bytes = await source();
      if (bytes == null) return;
      await widget.backup.restore(bytes);
      await _load();
    }, 'Sauvegarde restaurée');
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.backup;
    final list = backups;
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegardes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          const Text(
            'Les données du ménage, photos et notes vocales comprises. Une sauvegarde automatique est faite chaque jour ; les 7 dernières sont gardées sur le téléphone. Partagez-en une vers Drive ou par e-mail pour la garder ailleurs.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
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
          const SizedBox(height: 16),
          if (b.canBackup)
            NovaButton(
              'Sauvegarder maintenant',
              onPressed: busy
                  ? null
                  : () => run(() async {
                      await b.backupNow();
                      await _load();
                    }, 'Sauvegarde enregistrée'),
            ),
          if (b.canRestore) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _restore(widget.pick),
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Restaurer depuis un fichier'),
            ),
          ],
          const SizedBox(height: 22),
          const Text(
            'Sur ce téléphone',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (list == null && error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (list != null && list.isEmpty)
            const EmptyState(
              'Aucune sauvegarde',
              'La première sauvegarde automatique est faite à l’ouverture du module.',
            ),
          for (final (i, backup) in (list ?? const <BackupInfo>[]).indexed)
            FadeSlideIn(
              key: ValueKey(backup.path),
              index: i,
              child: Card(
                color: Colors.white,
                elevation: 0,
                child: ListTile(
                  leading: Icon(
                    backup.automatic ? Icons.schedule : Icons.save_outlined,
                    color: AppColors.primary,
                  ),
                  title: Text(shortDate(backup.createdAt)),
                  subtitle: Text(
                    '${backup.automatic ? 'Automatique' : 'Manuelle'} · ${sizeText(backup.size)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip:
                            'Partager la sauvegarde du ${shortDate(backup.createdAt)}',
                        onPressed: busy
                            ? null
                            : () => run(
                                () => widget.share(backup),
                                'Sauvegarde prête à partager',
                              ),
                        icon: const Icon(Icons.share_outlined),
                      ),
                      if (b.canRestore)
                        IconButton(
                          tooltip:
                              'Restaurer la sauvegarde du ${shortDate(backup.createdAt)}',
                          onPressed: busy
                              ? null
                              : () => _restore(() => b.readFile(backup.path)),
                          icon: const Icon(Icons.settings_backup_restore),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
