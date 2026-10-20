import 'package:flutter/material.dart';

import 'app/modules.dart';
import 'app/nova_app.dart';
import 'shared/services/app_database.dart';
import 'shared/services/app_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await AppDatabase.open(
    schemas: [for (final module in novaModules) ?module.schema],
  );
  final session = AppSession(
    database: database,
    staff: userManagement.staffDirectory,
  );
  attachModules(session);
  runApp(NovaApp(session: session));
}
