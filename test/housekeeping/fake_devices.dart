import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nova_paris/housekeeping/services/task_photo_picker.dart';
import 'package:nova_paris/housekeeping/services/voice_notes.dart';

import 'photo_fixture.dart';

/// Records nothing: remembers what the screens asked for.
class FakeVoiceNotes implements VoiceNotes {
  final started = <String>[], played = <String>[], deleted = <String>[];
  var stops = 0;
  bool denied = false;
  final _done = StreamController<void>.broadcast();

  @override
  Future<String> start() async {
    if (denied) throw StateError('Micro refusé.');
    final path =
        'housekeeping/voice/00000000-0000-4000-8000-${started.length.toString().padLeft(12, '0')}.m4a';
    started.add(path);
    return path;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> play(String path) async => played.add(path);

  @override
  Future<void> stopPlayback() async {}

  /// The playback reached the end.
  void finish() => _done.add(null);

  @override
  Stream<void> get playbackDone => _done.stream;

  @override
  Future<void> delete(String path) async => deleted.add(path);

  @override
  void dispose() {}
}

class FakePhotoPicker implements TaskPhotoPicker {
  var picks = 0;
  @override
  Future<Uint8List?> pick({required bool camera}) async {
    picks++;
    return photoBytes();
  }

  @override
  Future<Uint8List?> recover() async => null;
}
