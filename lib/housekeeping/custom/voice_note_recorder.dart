import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../models/issue.dart';
import '../services/voice_notes.dart';

String voiceDuration(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// Records one voice note (stops by itself at [maxVoiceSeconds]), plays it
/// back and deletes it. Reports the note with [onChanged] (null when none).
class VoiceNoteRecorder extends StatefulWidget {
  final VoiceNotes voice;
  final bool enabled;
  final void Function(String? path, int seconds) onChanged;
  const VoiceNoteRecorder({
    super.key,
    required this.voice,
    required this.onChanged,
    this.enabled = true,
  });
  @override
  State<VoiceNoteRecorder> createState() => _VoiceNoteRecorderState();
}

class _VoiceNoteRecorderState extends State<VoiceNoteRecorder> {
  String? _path;
  bool _recording = false, _playing = false, _starting = false;
  int _seconds = 0;
  Timer? _ticker;
  String? _error;
  StreamSubscription<void>? _done;

  @override
  void initState() {
    super.initState();
    _done = widget.voice.playbackDone.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _done?.cancel();
    if (_recording) unawaited(widget.voice.stop());
    if (_playing) unawaited(widget.voice.stopPlayback());
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final path = await widget.voice.start();
      if (!mounted) return;
      setState(() {
        _path = path;
        _recording = true;
        _seconds = 0;
      });
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _seconds++);
        if (_seconds >= maxVoiceSeconds) _stop();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    if (!_recording) return;
    setState(() => _recording = false);
    try {
      await widget.voice.stop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (_seconds < 1) {
      // Too short to be useful: nothing is kept.
      await _delete(
        message: 'Note trop courte. Maintenez l’enregistrement au moins une seconde.',
      );
      return;
    }
    widget.onChanged(_path, _seconds.clamp(1, maxVoiceSeconds));
  }

  Future<void> _togglePlay() async {
    try {
      if (_playing) {
        await widget.voice.stopPlayback();
        if (mounted) setState(() => _playing = false);
      } else {
        await widget.voice.play(_path!);
        if (mounted) setState(() => _playing = true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _delete({String? message}) async {
    final path = _path;
    if (_playing) await widget.voice.stopPlayback();
    setState(() {
      _path = null;
      _playing = false;
      _seconds = 0;
      _error = message;
    });
    widget.onChanged(null, 0);
    if (path != null) await widget.voice.delete(path);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.red, fontSize: 12),
              ),
            ),
          );
    if (_recording) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.redLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.fiber_manual_record, color: AppColors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      'Enregistrement · ${voiceDuration(_seconds)} / ${voiceDuration(maxVoiceSeconds)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                  onPressed: _stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Arrêter'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _seconds / maxVoiceSeconds,
              color: AppColors.red,
              backgroundColor: Colors.white,
            ),
          ],
        ),
      );
    }
    if (_path != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.greenLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: _playing ? 'Arrêter la lecture' : 'Écouter',
                  onPressed: widget.enabled ? _togglePlay : null,
                  icon: Icon(
                    _playing ? Icons.stop_circle_outlined : Icons.play_circle,
                    color: AppColors.primary,
                    size: 30,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Note vocale · ${voiceDuration(_seconds)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Supprimer la note vocale',
                  onPressed: widget.enabled ? _delete : null,
                  icon: const Icon(Icons.delete_outline, color: AppColors.red),
                ),
              ],
            ),
          ),
          ?error,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: widget.enabled && !_starting ? _start : null,
          icon: const Icon(Icons.mic_none),
          label: Text(
            'Note vocale (${voiceDuration(maxVoiceSeconds)} maximum)',
          ),
        ),
        ?error,
      ],
    );
  }
}

/// Plays a saved voice note.
class VoiceNotePlayer extends StatefulWidget {
  final VoiceNotes voice;
  final String path;
  final int seconds;
  const VoiceNotePlayer({
    super.key,
    required this.voice,
    required this.path,
    required this.seconds,
  });
  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  bool _playing = false;
  String? _error;
  StreamSubscription<void>? _done;

  @override
  void initState() {
    super.initState();
    _done = widget.voice.playbackDone.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _done?.cancel();
    if (_playing) unawaited(widget.voice.stopPlayback());
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await widget.voice.stopPlayback();
      } else {
        await widget.voice.play(widget.path);
      }
      if (mounted) {
        setState(() {
          _playing = !_playing;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.greenLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: _playing ? 'Arrêter la lecture' : 'Écouter',
              onPressed: _toggle,
              icon: Icon(
                _playing ? Icons.stop_circle_outlined : Icons.play_circle,
                color: AppColors.primary,
                size: 30,
              ),
            ),
            Expanded(
              child: Text(
                'Note vocale · ${voiceDuration(widget.seconds)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _error!,
            style: const TextStyle(color: AppColors.red, fontSize: 12),
          ),
        ),
    ],
  );
}
