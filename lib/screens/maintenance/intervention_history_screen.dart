import 'package:flutter/material.dart';

import '../../models/intervention.dart';
import '../../services/maintenance_service.dart';
import 'intervention_detail_screen.dart';
import 'maintenance_theme.dart';
import 'widgets/intervention_card.dart';
import 'widgets/maintenance_header.dart';

/// Historique : interventions résolues.
class InterventionHistoryScreen extends StatefulWidget {
  const InterventionHistoryScreen({super.key});

  @override
  State<InterventionHistoryScreen> createState() =>
      _InterventionHistoryScreenState();
}

class _InterventionHistoryScreenState extends State<InterventionHistoryScreen> {
  List<Intervention> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await MaintenanceService.getResolved();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.cream,
      body: SafeArea(
        child: RefreshIndicator(
          color: MC.terra,
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MaintenanceHeader(backTitle: 'Historique'),
                const SizedBox(height: 24),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child:
                        Center(child: CircularProgressIndicator(color: MC.terra)),
                  )
                else if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('Aucune intervention résolue.',
                          style: mt(13, color: MC.muted)),
                    ),
                  )
                else
                  for (final item in _items) ...[
                    InterventionCard(
                      intervention: item,
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              InterventionDetailScreen(interventionId: item.id),
                        ));
                        if (mounted) _load();
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
