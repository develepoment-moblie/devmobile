import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

// Saves the screenshots and the step results of
// integration_test/api_phone_test.dart in build/api_phone_test/.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/api_phone_test/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final file = File('build/api_phone_test/steps.json');
    await file.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'steps': data?['steps']}),
    );
  },
);
