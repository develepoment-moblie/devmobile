import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../shared/custom/app_theme.dart';
import '../shared/services/app_session.dart';
import 'home_shell.dart';
import 'modules.dart';

// The only MaterialApp. Modules never create their own.
class NovaApp extends StatelessWidget {
  final AppSession session;
  const NovaApp({super.key, required this.session});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nova Paris',
    debugShowCheckedModeBanner: false,
    theme: novaTheme(),
    locale: const Locale('fr'),
    supportedLocales: const [Locale('fr')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    // Transparent status bar so screens reach the top edge.
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
      ),
      child: child!,
    ),
    home: ListenableBuilder(
      listenable: session,
      builder: (context, _) => session.user == null
          ? userManagement.buildLogin(context, session)
          : HomeShell(
              // A new key resets navigation when the user or role changes.
              key: ValueKey('${session.user!.id}/${session.user!.role}'),
              session: session,
            ),
    ),
  );
}
