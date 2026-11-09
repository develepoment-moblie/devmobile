import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

// Saves the screenshots and the step results of
// integration_test/full_module_test.dart in build/phone_test/.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/phone_test/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final file = File('build/phone_test/steps.json');
    await file.create(recursive: true);
    // The steps only: the screenshots are already saved as PNG files.
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'steps': data?['steps']}),
    );
  },
);
