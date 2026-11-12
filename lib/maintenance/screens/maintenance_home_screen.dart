import 'package:flutter/material.dart';

import '../models/intervention.dart';
import '../../shared/services/app_session.dart';
import '../services/maintenance_store.dart';
import '../services/weather_maintenance_service.dart';
import 'intervention_detail_screen.dart';
import 'intervention_history_screen.dart';
import '../custom/maintenance_theme.dart';
import 'report_problem_screen.dart';
import '../custom/add_photo_card.dart';
import '../custom/intervention_card.dart';
import '../custom/maintenance_header.dart';
import '../custom/maintenance_summary_card.dart';
import '../custom/report_problem_button.dart';

/// Premier écran du module : résumé, signalement et interventions en cours.
class MaintenanceHomeScreen extends StatefulWidget {
  final AppSession session;
  const MaintenanceHomeScreen({super.key, required this.session});

  @override
  State<MaintenanceHomeScreen> createState() => _MaintenanceHomeScreenState();
}

class _MaintenanceHomeScreenState extends State<MaintenanceHomeScreen> {
  late final _store = MaintenanceStore(widget.session.database.database);
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
      final items = await _store.active();
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

  /// Maintenance prédictive : crée en arrière-plan les alertes météo
  /// (aucun changement visuel : elles apparaissent dans la liste).
  Future<void> _checkWeather() async {
    final created = await WeatherMaintenanceService.runIfDue(_store);
    if (created > 0 && mounted) await _load();
  }

  Future<void> _refresh() async {
    await _load();
    await _checkWeather();
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
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MaintenanceHeader(backTitle: 'Maintenance'),
              const SizedBox(height: 22),
              MaintenanceSummaryCard(activeCount: _items.length),
              const SizedBox(height: 12),
              ReportProblemButton(
                onPressed: () =>
                    _open(ReportProblemScreen(session: widget.session)),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Text(
                    'Interventions en cours',
                    style: mt(16, weight: FontWeight.w700),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _open(
                      InterventionHistoryScreen(session: widget.session),
                    ),
                    child: Text(
                      'Historique',
                      style: mt(12, weight: FontWeight.w700, color: MC.terra),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._buildList(),
              const SizedBox(height: 2),
              AddPhotoCard(
                onTap: () => _open(
                  ReportProblemScreen(
                    session: widget.session,
                    startWithPhoto: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

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
            child: Text(
              'Aucune intervention en cours.',
              style: mt(13, color: MC.muted),
            ),
          ),
        ),
      ];
    }
    return [
      for (final item in _items) ...[
        InterventionCard(
          intervention: item,
          onTap: () => _open(
            InterventionDetailScreen(
              session: widget.session,
              interventionId: item.id,
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }
}
