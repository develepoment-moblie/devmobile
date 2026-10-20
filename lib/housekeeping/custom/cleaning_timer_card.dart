import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../models/hotel_data.dart';
import '../models/room.dart';
import 'housekeeping_widgets.dart';

/// "1:05:09" or "12:04".
String formatElapsed(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

// The cleaning timer of a room: the assigned agent pauses, resumes or stops
// it; the supervisor sees it. The time comes from the stored segments, so it
// keeps counting after the app is closed and reopened.
class CleaningTimerCard extends StatefulWidget {
  final HotelData data;
  final Room room;
  const CleaningTimerCard({super.key, required this.data, required this.room});
  @override
  State<CleaningTimerCard> createState() => _CleaningTimerCardState();
}

class _CleaningTimerCardState extends State<CleaningTimerCard> {
  Timer? _tick;
  bool _busy = false;

  bool get _running => widget.room.timerState == 'running';

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(CleaningTimerCard old) {
    super.didUpdateWidget(old);
    _sync();
  }

  // Ticks every second only while the timer runs.
  void _sync() {
    if (_running && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_running) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _do(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showFeedback(context, done);
    } catch (e) {
      if (mounted) showFeedback(context, e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _sync();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room, data = widget.data;
    final state = room.timerState;
    final control = data.canControlTimer(room);
    if (state == null && !control) return const SizedBox.shrink();
    final (label, color, icon) = switch (state) {
      'running' => ('En cours', AppColors.green, Icons.timer_outlined),
      'paused' => ('En pause', AppColors.orange, Icons.pause_circle_outline),
      'stopped' => ('Arrêté', AppColors.primary, Icons.flag_outlined),
      _ => ('Non lancé', AppColors.gray, Icons.timer_off_outlined),
    };
    final shown = state == 'stopped' && room.timerDuration != null
        ? room.timerDuration!
        : room.elapsed();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .35)),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Minuteur · $label',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(
            liveRegion: false,
            label: 'Temps de nettoyage ${formatElapsed(shown)}',
            excludeSemantics: true,
            child: Text(
              formatElapsed(shown),
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Text(
            state == 'stopped'
                ? 'Temps réel de nettoyage, pauses exclues.'
                : 'Les pauses ne comptent pas dans le temps de nettoyage.',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (control) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (state == 'running')
                  FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () => _do(
                            () => data.pauseTimer(room),
                            'Minuteur en pause',
                          ),
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () => _do(
                            () => data.resumeTimer(room),
                            'Minuteur relancé',
                          ),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      state == null ? 'Lancer le minuteur' : 'Reprendre',
                    ),
                  ),
                if (state == 'running' || state == 'paused')
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _do(
                            () => data.stopTimer(room),
                            'Minuteur arrêté',
                          ),
                    icon: const Icon(Icons.stop),
                    label: const Text('Arrêter'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
