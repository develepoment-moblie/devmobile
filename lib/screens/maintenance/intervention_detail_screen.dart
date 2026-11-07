import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../models/intervention.dart';
import '../../services/auth_service.dart';
import '../../services/maintenance_service.dart';
import 'maintenance_theme.dart';
import 'widgets/maintenance_header.dart';
import 'widgets/photo_picker.dart';
import 'widgets/status_badge.dart';

/// Détail d'une intervention + actions selon le rôle :
///  - maintenance : « Prendre en charge » puis « Marquer comme résolu »
///  - manager / admin : attribuer à un technicien, résoudre, supprimer
///  - autres rôles (staff) : consultation + ajout de photos
class InterventionDetailScreen extends StatefulWidget {
  final int interventionId;
  const InterventionDetailScreen({super.key, required this.interventionId});

  @override
  State<InterventionDetailScreen> createState() =>
      _InterventionDetailScreenState();
}

class _InterventionDetailScreenState extends State<InterventionDetailScreen> {
  Intervention? _item;
  List<Uint8List> _photos = [];
  bool _loading = true;
  bool _busy = false;

  AppUser? get _me => AuthService.currentUser;
  int? get _myId => int.tryParse(_me?.id ?? '');
  bool get _isManager => _me?.role == 'admin' || _me?.role == 'manager';
  bool get _isTech => _me?.role == 'maintenance';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final item = await MaintenanceService.getById(widget.interventionId);
      final photos = item == null
          ? <Uint8List>[]
          : await MaintenanceService.getPhotos(item.id);
      if (!mounted) return;
      setState(() {
        _item = item;
        _photos = photos;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(Future<void> Function() action, String successMsg) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      _snack(successMsg);
    } catch (_) {
      _snack('Une erreur est survenue.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto() async {
    final bytes = await pickInterventionPhoto(context);
    if (bytes == null) return;
    await _run(
      () => MaintenanceService.addPhoto(widget.interventionId, bytes),
      'Photo ajoutée.',
    );
  }

  Future<void> _assign() async {
    final techs = await MaintenanceService.getTechnicians();
    if (!mounted) return;
    if (techs.isEmpty) {
      _snack("Aucun technicien (rôle « maintenance ») n'existe.");
      return;
    }
    final chosen = await showModalBottomSheet<AppUser>(
      context: context,
      backgroundColor: MC.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text('Attribuer à un technicien',
                style: mt(15, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final t in techs)
              ListTile(
                leading: const Icon(Icons.person_outline, color: MC.dark),
                title: Text(t.displayName, style: mt(14, weight: FontWeight.w600)),
                subtitle: Text(t.fullName, style: mt(11, color: MC.muted)),
                onTap: () => Navigator.pop(ctx, t),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await _run(
      () => MaintenanceService.assign(widget.interventionId, int.parse(chosen.id)),
      'Attribuée à ${chosen.displayName}.',
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette intervention ?'),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MaintenanceService.delete(widget.interventionId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      _snack('Suppression impossible.');
    }
  }

  void _showPhoto(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain)),
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MaintenanceHeader(backTitle: 'Détail intervention'),
              const SizedBox(height: 22),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator(color: MC.terra)),
                )
              else if (_item == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text('Intervention introuvable.',
                        style: mt(13, color: MC.muted)),
                  ),
                )
              else
                ..._buildContent(_item!),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(Intervention i) {
    final canTake = _isTech &&
        i.status == InterventionStatus.pending &&
        (i.assigneeId == null || i.assigneeId == _myId);
    final canResolve = i.status == InterventionStatus.inProgress &&
        (_isManager || (_isTech && i.assigneeId == _myId));
    final canAssign = _isManager && !i.isResolved;

    return [
      // ===== Carte principale =====
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: MC.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusBadge(
                  label: i.priority.label,
                  background: i.priority.background,
                  foreground: i.priority.foreground,
                ),
                StatusBadge(
                  label: i.status.label,
                  background: i.status.background,
                  foreground: i.status.foreground,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(i.title, style: mt(20, weight: FontWeight.w700)),
            const SizedBox(height: 14),
            _InfoRow(Icons.meeting_room_outlined, 'Chambre', i.room),
            _InfoRow(i.category.icon, 'Catégorie', i.category.label),
            _InfoRow(Icons.person_outline, 'Signalé par',
                i.reporterName ?? 'Inconnu'),
            _InfoRow(Icons.engineering_outlined, 'Technicien',
                i.assigneeName ?? 'Non assignée'),
            _InfoRow(Icons.schedule, 'Créée le', _fmt(i.createdAt)),
            if (i.resolvedAt != null)
              _InfoRow(Icons.check_circle_outline, 'Résolue le',
                  _fmt(i.resolvedAt!)),
          ],
        ),
      ),

      // ===== Description =====
      if (i.description.isNotEmpty) ...[
        const SizedBox(height: 22),
        Text('Description', style: mt(15, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(i.description, style: mt(13, color: MC.text, height: 1.4)),
      ],

      // ===== Photos =====
      const SizedBox(height: 22),
      Row(
        children: [
          Text('Photos', style: mt(15, weight: FontWeight.w700)),
          const Spacer(),
          if (!i.isResolved)
            GestureDetector(
              onTap: _busy ? null : _addPhoto,
              child: Text('+ Ajouter',
                  style: mt(12, weight: FontWeight.w700, color: MC.terra)),
            ),
        ],
      ),
      const SizedBox(height: 10),
      if (_photos.isEmpty)
        Text('Aucune photo.', style: mt(12, color: MC.muted))
      else
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, k) => GestureDetector(
              onTap: () => _showPhoto(_photos[k]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_photos[k],
                    width: 96, height: 96, fit: BoxFit.cover),
              ),
            ),
          ),
        ),

      // ===== Actions =====
      const SizedBox(height: 28),
      if (canTake)
        _ActionButton(
          label: 'Prendre en charge',
          icon: Icons.play_arrow_rounded,
          busy: _busy,
          onTap: () => _run(
            () => MaintenanceService.takeCharge(i.id, _myId!),
            'Intervention prise en charge.',
          ),
        ),
      if (canResolve) ...[
        if (canTake) const SizedBox(height: 10),
        _ActionButton(
          label: 'Marquer comme résolu',
          icon: Icons.check_rounded,
          busy: _busy,
          onTap: () => _run(
            () => MaintenanceService.markResolved(i.id),
            'Intervention résolue.',
          ),
        ),
      ],
      if (canAssign) ...[
        const SizedBox(height: 10),
        _ActionButton(
          label: i.assigneeId == null ? 'Attribuer à un technicien' : 'Réattribuer',
          icon: Icons.person_add_alt_outlined,
          outlined: true,
          busy: _busy,
          onTap: _assign,
        ),
      ],
      if (_isManager) ...[
        const SizedBox(height: 10),
        _ActionButton(
          label: 'Supprimer',
          icon: Icons.delete_outline,
          outlined: true,
          danger: true,
          busy: _busy,
          onTap: _delete,
        ),
      ],
    ];
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: MC.dark),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(label, style: mt(11.5, color: MC.muted)),
          ),
          Expanded(
            child: Text(value, style: mt(12.5, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool outlined;
  final bool danger;
  final bool busy;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.outlined = false,
    this.danger = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(15);
    final fg = outlined ? (danger ? MC.urgentFg : MC.dark) : Colors.white;

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: outlined ? Colors.white : MC.terra,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: outlined
              ? BorderSide(color: danger ? MC.urgentFg : MC.border)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Text(label, style: mt(13.5, weight: FontWeight.w700, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
