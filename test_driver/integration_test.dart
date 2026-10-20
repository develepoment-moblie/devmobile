import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

// Saves the screenshots taken by integration_test/screen_tour_test.dart.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/screen_tour/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
