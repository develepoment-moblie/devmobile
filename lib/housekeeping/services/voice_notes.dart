import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'app_exception.dart';
import 'mutation_meta.dart';

/// Records and plays the voice note of a problem report. Files live in the
/// app's documents folder under `housekeeping/voice/<uuid>.m4a`; SQLite keeps
/// only that relative path.
abstract interface class VoiceNotes {
  /// Starts recording; returns the relative path of the new file.
  /// Throws when the microphone permission is refused.
  Future<String> start();

  /// Stops recording; the file is complete.
  Future<void> stop();

  Future<void> play(String path);
  Future<void> stopPlayback();

  /// Fires when a playback reaches the end.
  Stream<void> get playbackDone;

  /// Deletes a recording that was not sent (cancelled report).
  Future<void> delete(String path);
  void dispose();
}

// The recorder and player are created on first use: opening a report
// without recording touches neither the microphone nor the audio plugins.
class DeviceVoiceNotes implements VoiceNotes {
  AudioRecorder? _recorderInstance;
  AudioPlayer? _playerInstance;
  StreamSubscription<void>? _completion;
  final _done = StreamController<void>.broadcast();

  AudioRecorder get _recorder => _recorderInstance ??= AudioRecorder();
  AudioPlayer get _player {
    if (_playerInstance case final player?) return player;
    final player = _playerInstance = AudioPlayer();
    _completion = player.onPlayerComplete.listen(_done.add);
    return player;
  }

  static Future<String> _absolute(String relative) async =>
      p.join((await getApplicationDocumentsDirectory()).path, relative);

  @override
  Future<String> start() async {
    if (!await _recorder.hasPermission()) {
      throw const AppServiceException(
        'Micro refusé. Autorisez le micro pour Nova Paris dans les réglages du téléphone.',
      );
    }
    final relative = 'housekeeping/voice/${uuidV4()}.m4a';
    final file = File(await _absolute(relative));
    await file.parent.create(recursive: true);
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
      path: file.path,
    );
    return relative;
  }

  @override
  Future<void> stop() async {
    await _recorderInstance?.stop();
  }

  @override
  Future<void> play(String path) async {
    final file = File(await _absolute(path));
    if (!await file.exists()) {
      throw const AppServiceException(
        'Note vocale introuvable sur ce téléphone.',
      );
    }
    await _player.stop();
    await _player.play(DeviceFileSource(file.path));
  }

  @override
  Future<void> stopPlayback() async {
    await _playerInstance?.stop();
  }

  @override
  Stream<void> get playbackDone => _done.stream;

  @override
  Future<void> delete(String path) async {
    final file = File(await _absolute(path));
    if (await file.exists()) await file.delete();
  }

  @override
  void dispose() {
    unawaited(_completion?.cancel());
    unawaited(_recorderInstance?.dispose());
    unawaited(_playerInstance?.dispose());
    unawaited(_done.close());
  }
}
