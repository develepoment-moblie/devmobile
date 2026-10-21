import 'package:flutter/material.dart';

import '../../shared/custom/animations.dart';
import '../../shared/custom/app_theme.dart';
import '../custom/housekeeping_widgets.dart';
import '../custom/roomcard.dart';
import '../custom/voice_note_recorder.dart';
import '../models/hotel_data.dart';
import '../models/issue.dart';
import '../services/voice_notes.dart';

String issueDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

(Color, Color) issueTone(IssueStatus status) => switch (status) {
  IssueStatus.open => (AppColors.orange, AppColors.orangeLight),
  IssueStatus.resolved => (AppColors.green, AppColors.greenLight),
  IssueStatus.closed => (AppColors.gray, AppColors.grayLight),
};

(Color, Color) priorityTone(IssuePriority priority) => switch (priority) {
  IssuePriority.urgent => (AppColors.red, AppColors.redLight),
  IssuePriority.high => (AppColors.orange, AppColors.orangeLight),
  _ => (AppColors.gray, AppColors.grayLight),
};

// "Signalements": every report for the supervisor, their own for an agent,
// filtered by status. [roomNumber] limits the list to one room.
class IssuesScreen extends StatefulWidget {
  final HotelData data;
  final String? roomNumber;
  const IssuesScreen({super.key, required this.data, this.roomNumber});
  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  var status = IssueStatus.open;

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

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final all = [
      for (final i in data.issues)
        if (widget.roomNumber == null || i.roomNumber == widget.roomNumber) i,
    ];
    final shown = [
      for (final i in all)
        if (i.status == status) i,
    ];
    final title = widget.roomNumber != null
        ? 'Signalements · ${widget.roomNumber}'
        : data.isSupervisor
        ? 'Signalements'
        : 'Mes signalements';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: RefreshIndicator(
        onRefresh: data.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in IssueStatus.values)
                  ChoiceChip(
                    label: Text(
                      '${switch (s) {
                        IssueStatus.open => 'Signalés',
                        IssueStatus.resolved => 'Résolus',
                        IssueStatus.closed => 'Clôturés',
                      }} · ${all.where((i) => i.status == s).length}',
                    ),
                    selected: status == s,
                    onSelected: (_) => setState(() => status = s),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (shown.isEmpty)
              EmptyState(
                switch (status) {
                  IssueStatus.open => 'Aucun problème en attente',
                  IssueStatus.resolved => 'Aucune intervention terminée',
                  IssueStatus.closed => 'Aucun signalement clôturé',
                },
                switch (status) {
                  IssueStatus.open =>
                    'Signalez un problème depuis la fiche d’une chambre.',
                  IssueStatus.resolved => 'Les problèmes réparés par la maintenance apparaîtront ici.',
                  IssueStatus.closed =>
                    'Les signalements terminés sont archivés ici.',
                },
              ),
            for (final (i, issue) in shown.indexed)
              FadeSlideIn(
                key: ValueKey('${status.name}-${issue.id}'),
                index: i,
                child: IssueCard(
                  issue: issue,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          IssueDetailScreen(data: data, issueId: issue.id),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class IssueCard extends StatelessWidget {
  final Issue issue;
  final VoidCallback onTap;
  const IssueCard({super.key, required this.issue, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (color, background) = issueTone(issue.status);
    final (pColor, pBackground) = priorityTone(issue.priority);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(issue.category.icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chambre ${issue.roomNumber} · ${issue.category.label}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        issue.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusBadge(
                            issue.status.label,
                            color: color,
                            background: background,
                          ),
                          StatusBadge(
                            issue.priority.label,
                            color: pColor,
                            background: pBackground,
                          ),
                          if (issue.outOfService)
                            const StatusBadge(
                              'Hors service',
                              color: AppColors.red,
                              background: AppColors.redLight,
                            ),
                          if (issue.photoIds.isNotEmpty)
                            Semantics(
                              label: '${issue.photoIds.length} photo(s)',
                              child: const Icon(
                                Icons.image_outlined,
                                size: 16,
                                color: AppColors.muted,
                              ),
                            ),
                          if (issue.voicePath != null)
                            const Icon(
                              Icons.mic_none,
                              size: 16,
                              color: AppColors.muted,
                              semanticLabel: 'Note vocale',
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${issue.reportedByName} · ${issueDate(issue.reportedAt)}',
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
          ),
        ),
      ),
    );
  }
}

// One report: photos, voice note, timeline and the supervisor's actions.
class IssueDetailScreen extends StatefulWidget {
  final HotelData data;
  final String issueId;
  const IssueDetailScreen({
    super.key,
    required this.data,
    required this.issueId,
  });
  @override
  State<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends State<IssueDetailScreen> {
  late final VoiceNotes _voice = widget.data.createVoiceNotes();
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
    _voice.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) showFeedback(context, done);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmClose(Issue issue) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clôturer ce signalement ?'),
        content: Text(
          issue.outOfService && issue.status == IssueStatus.open
              ? 'Le suivi s’arrête, mais la chambre reste hors service jusqu’à la fin de l’intervention.'
              : 'Le signalement passe dans les signalements clôturés.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => widget.data.closeIssue(issue), 'Signalement clôturé');
    }
  }

  Future<void> _photo(Issue issue, String photoId, int n) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Photo $n · chambre ${issue.roomNumber}'),
      content: FutureBuilder(
        future: widget.data.issuePhoto(issue, photoId),
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

  Widget _step(
    IconData icon,
    Color color,
    String title,
    String when,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                when,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final issue = data.issues.where((i) => i.id == widget.issueId).firstOrNull;
    if (issue == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Signalement')),
        body: const Padding(
          padding: EdgeInsets.all(18),
          child: EmptyState(
            'Signalement indisponible',
            'Ce signalement n’est plus accessible. Revenez à la liste.',
          ),
        ),
      );
    }
    final (color, background) = issueTone(issue.status);
    final (pColor, pBackground) = priorityTone(issue.priority);
    return Scaffold(
      appBar: AppBar(title: Text('Signalement · ${issue.roomNumber}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          if (_busy) const LinearProgressIndicator(),
          StaffBanner(
            title: issue.category.label,
            label: 'CHAMBRE ${issue.roomNumber}',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge(
                issue.status.label,
                color: color,
                background: background,
              ),
              StatusBadge(
                'Priorité ${issue.priority.label.toLowerCase()}',
                color: pColor,
                background: pBackground,
              ),
              if (issue.outOfService)
                const StatusBadge(
                  'Chambre hors service',
                  color: AppColors.red,
                  background: AppColors.redLight,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(issue.description, style: const TextStyle(fontSize: 15)),
          if (issue.photoIds.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (n, id) in issue.photoIds.indexed)
                  OutlinedButton.icon(
                    onPressed: () => _photo(issue, id, n + 1),
                    icon: const Icon(Icons.image_outlined),
                    label: Text('Photo ${n + 1}'),
                  ),
              ],
            ),
          ],
          if (issue.voicePath != null) ...[
            const SizedBox(height: 16),
            VoiceNotePlayer(
              voice: _voice,
              path: issue.voicePath!,
              seconds: issue.voiceSeconds ?? 0,
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Suivi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _step(
            Icons.report_outlined,
            AppColors.orange,
            'Signalé par ${issue.reportedByName}',
            issueDate(issue.reportedAt),
          ),
          if (issue.resolvedAt != null)
            _step(
              Icons.build_circle_outlined,
              AppColors.green,
              'Intervention terminée par la maintenance',
              issueDate(issue.resolvedAt!),
            ),
          if (issue.closedAt != null)
            _step(
              Icons.task_alt,
              AppColors.gray,
              'Clôturé par ${issue.closedByName ?? 'la gouvernante'}',
              issueDate(issue.closedAt!),
            ),
          if (issue.status == IssueStatus.open)
            const Text(
              'En attente de la maintenance.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.red),
              ),
            ),
          ],
          if (data.canBringBack(issue)) ...[
            const SizedBox(height: 16),
            NovaButton(
              'Remettre à nettoyer',
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => data.bringBack(issue),
                      'Chambre ${issue.roomNumber} remise à nettoyer',
                    ),
            ),
          ],
          if (data.isSupervisor && issue.status != IssueStatus.closed) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : () => _confirmClose(issue),
              child: const Text('Clôturer le signalement'),
            ),
          ],
        ],
      ),
    );
  }
}
