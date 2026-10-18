import 'package:flutter/material.dart';

import '../shared/custom/app_widgets.dart';
import '../shared/custom/draft_guard.dart';
import '../shared/services/backup_codec.dart';
import '../user_management/services/user_repository.dart';
import 'backup_files.dart';
import 'backup_service.dart';

class BackupScreen extends StatefulWidget {
  final BackupService service;
  final BackupFiles? files;
  const BackupScreen({super.key, required this.service, this.files});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _exportForm = GlobalKey<FormState>(),
      _restoreForm = GlobalKey<FormState>();
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  final _restorePassword = TextEditingController();
  late final _files = widget.files ?? NativeBackupFiles();
  BackupFile? _file;
  BackupContents? _preview;
  bool _busy = false, _confirming = false;
  String? _error, _notice;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    _restorePassword.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    if (!_exportForm.currentState!.validate()) return;
    await _run(() async {
      final bytes = await widget.service.create(_password.text);
      final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        ':',
        '-',
      );
      final saved = await _files.save(
        'nova-paris-$timestamp.nova-backup',
        bytes,
      );
      if (!mounted) return;
      if (saved) {
        _password.clear();
        _confirmation.clear();
      }
      _notice = saved
          ? 'Sauvegarde enregistrée à l’emplacement choisi.'
          : 'Enregistrement annulé.';
    });
  }

  Future<void> _pick() => _run(() async {
    final file = await _files.pick();
    if (!mounted || file == null) return;
    _file = file;
    _preview = null;
    _restorePassword.clear();
  });

  Future<void> _inspect() async {
    if (!_restoreForm.currentState!.validate() || _file == null) return;
    await _run(() async {
      _preview = null;
      final contents = await widget.service.inspect(
        _file!.bytes,
        _restorePassword.text,
      );
      if (mounted) _preview = contents;
    });
  }

  String _date(DateTime date) {
    final local = date.toLocal(), labels = MaterialLocalizations.of(context);
    return '${labels.formatMediumDate(local)} à ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: true)}';
  }

  Future<void> _restore() async {
    final preview = _preview;
    if (_busy || _confirming || preview == null) return;
    _confirming = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Remplacer les données locales ?'),
        content: Text(
          'Toutes les données actuelles de cet appareil seront remplacées par la sauvegarde du ${_date(preview.createdAt)}. Les comptes et mots de passe seront ceux de cette sauvegarde. Vous serez déconnecté.\n\nExportez d’abord une sauvegarde des données actuelles si vous souhaitez les conserver.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remplacer les données'),
          ),
        ],
      ),
    );
    _confirming = false;
    if (!mounted || confirmed != true) return;
    await _run(() async {
      await widget.service.restore(preview);
      if (mounted) {
        _restorePassword.clear();
        _preview = null;
        _file = null;
        _notice = 'Sauvegarde restaurée. Reconnectez-vous.';
        showFeedback(context, _notice!);
      }
    });
  }

  Widget _passwordField(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    enabled: !_busy,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
    maxLength: 256,
    decoration: InputDecoration(labelText: label, counterText: ''),
    validator: validator,
    onChanged: controller == _restorePassword
        ? (_) => setState(() => _preview = null)
        : null,
  );

  @override
  Widget build(BuildContext context) => DraftGuard(
    dirty: false,
    busy: _busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Sauvegarde des données')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Protégez les données de cet appareil',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'La sauvegarde contient les utilisateurs, les chambres, le ménage, le stock et les notifications. Enregistrez-la hors du stockage privé de l’application pour la conserver après une réinstallation.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Le fichier est chiffré avec le mot de passe choisi. Gardez ce mot de passe : il ne peut pas être récupéré.',
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(
              semanticsLabel: 'Opération de sauvegarde en cours',
            ),
            const SizedBox(height: 8),
            const Text('Veuillez patienter…'),
          ],
          if (_error != null || _notice != null) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                _error ?? _notice!,
                style: TextStyle(
                  color: _error != null
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          const Text(
            'Créer une sauvegarde',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Form(
            key: _exportForm,
            child: Column(
              children: [
                _passwordField(
                  _password,
                  'Mot de passe de la sauvegarde',
                  validator: (v) => v == null || v.length < 8
                      ? 'Choisissez au moins 8 caractères.'
                      : null,
                ),
                const SizedBox(height: 12),
                _passwordField(
                  _confirmation,
                  'Confirmer le mot de passe',
                  validator: (v) => v != _password.text
                      ? 'Les mots de passe doivent être identiques.'
                      : null,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _export,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Exporter la sauvegarde'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            'Restaurer une sauvegarde',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Fichier Nova Paris (.nova-backup), 64 Mo maximum, photos comprises. La restauration remplace toutes les données locales et ferme la session.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.folder_open),
            label: const Text('Choisir un fichier'),
          ),
          if (_file != null) ...[
            const SizedBox(height: 12),
            Text(
              'Fichier : ${_file!.name}',
              overflow: TextOverflow.ellipsis,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Form(
              key: _restoreForm,
              child: _passwordField(
                _restorePassword,
                'Mot de passe du fichier',
                validator: (v) => v == null || v.isEmpty
                    ? 'Saisissez le mot de passe de cette sauvegarde.'
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : _inspect,
              child: const Text('Vérifier la sauvegarde'),
            ),
          ],
          if (_preview case final preview?) ...[
            const SizedBox(height: 16),
            Text(
              'Sauvegarde du ${_date(preview.createdAt)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '${preview.users} utilisateurs actifs · ${preview.rooms} chambres · ${preview.archivedRooms} chambres archivées · ${preview.supplies} articles de stock',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _restore,
              child: const Text('Restaurer cette sauvegarde'),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}
