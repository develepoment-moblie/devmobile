import 'package:flutter/material.dart';

import '../../models/intervention.dart';
import '../../services/maintenance_service.dart';
import 'intervention_detail_screen.dart';
import 'intervention_history_screen.dart';
import 'maintenance_theme.dart';
import 'report_problem_screen.dart';
import 'widgets/add_photo_card.dart';
import 'widgets/intervention_card.dart';
import 'widgets/maintenance_header.dart';
import 'widgets/maintenance_summary_card.dart';
import 'widgets/report_problem_button.dart';

/// Écran « Maintenance » : résumé, signalement et interventions en cours.
///
/// [asTab] = true  → utilisé comme onglet d'accueil du rôle `maintenance`
///                   (pas de Scaffold, logo + cloche en en-tête).
/// [asTab] = false → ouvert depuis Accès rapide (bouton retour + titre).
class MaintenanceScreen extends StatefulWidget {
  final bool asTab;
  const MaintenanceScreen({super.key, this.asTab = false});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  List<Intervention> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await MaintenanceService.getActive();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les interventions.';
      });
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: MC.terra,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MaintenanceHeader(backTitle: widget.asTab ? null : 'Maintenance'),
              const SizedBox(height: 22),
              MaintenanceSummaryCard(activeCount: _items.length),
              const SizedBox(height: 12),
              ReportProblemButton(
                onPressed: () => _open(const ReportProblemScreen()),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Text('Interventions en cours',
                      style: mt(16, weight: FontWeight.w700)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _open(const InterventionHistoryScreen()),
                    child: Text('Historique',
                        style: mt(12, weight: FontWeight.w700, color: MC.terra)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._buildList(),
              const SizedBox(height: 2),
              AddPhotoCard(
                onTap: () =>
                    _open(const ReportProblemScreen(startWithPhoto: true)),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.asTab) return body;
    return Scaffold(backgroundColor: MC.cream, body: body);
  }

  List<Widget> _buildList() {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator(color: MC.terra)),
        ),
      ];
    }
    if (_error != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Column(
              children: [
                Text(_error!, style: mt(13, color: MC.muted)),
                const SizedBox(height: 8),
                TextButton(onPressed: _load, child: const Text('Réessayer')),
              ],
            ),
          ),
        ),
      ];
    }
    if (_items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('Aucune intervention en cours.',
                style: mt(13, color: MC.muted)),
          ),
        ),
      ];
    }
    return [
      for (final item in _items) ...[
        InterventionCard(
          intervention: item,
          onTap: () => _open(InterventionDetailScreen(interventionId: item.id)),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }
}
