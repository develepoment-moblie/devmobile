import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/app/back_navigation.dart';
import 'package:nova_paris/app/main_screen.dart';
import 'package:nova_paris/housekeeping/models/hotel_data.dart';
import 'package:nova_paris/housekeeping/screens/details_screen.dart';
import 'package:nova_paris/housekeeping/screens/notifications_screen.dart';
import 'package:nova_paris/main.dart';
import 'package:nova_paris/user_management/screens/login_screen.dart';
import 'package:nova_paris/user_management/screens/manage_users.dart';

import 'user_merge_test.dart' show FakeUsers, FakeHousekeeping;

class PendingCreateUsers extends FakeUsers {
  final saving = Completer<void>();
  @override
  Future<void> createUser(
    String email,
    String password,
    String name,
    String role,
  ) async {
    await saving.future;
    await super.createUser(email, password, name, role);
  }
}

void main() {
  late int exits;
  setUp(() {
    exits = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exits++;
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<FakeUsers> open(
    WidgetTester tester, {
    String? role = 'manager',
    FakeUsers? users,
  }) async {
    final auth = (users ?? FakeUsers())..active = role;
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await auth.changes.close();
    });
    await tester.pumpWidget(
      NovaParisApp(
        auth: auth,
        housekeepingFactory: () => FakeHousekeeping(auth),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('phone Back pops the authenticated page before offering exit', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Gérer les utilisateurs'));
    await tester.pumpAndSettle();
    expect(find.byType(ManageUsersScreen), findsOneWidget);
    await back(tester);
    expect(find.byType(ManageUsersScreen), findsNothing);
    expect(find.text('Espace manager'), findsOneWidget);
    expect(find.text(AppBackNavigation.exitMessage), findsNothing);
    expect(exits, 0);

    await back(tester);
    expect(find.text(AppBackNavigation.exitMessage), findsOneWidget);
    expect(exits, 0);
    await back(tester);
    expect(exits, 1);
  });

  testWidgets('exit confirmation expires and navigation cancels it', (
    tester,
  ) async {
    await open(tester);
    await back(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await back(tester);
    expect(exits, 0);

    await tester.tap(find.text('Gérer les utilisateurs'));
    await tester.pumpAndSettle();
    await back(tester);
    await back(tester);
    expect(exits, 0);
    expect(find.text(AppBackNavigation.exitMessage), findsOneWidget);
  });

  testWidgets('Back closes a pristine form sheet before its parent page', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Gérer les utilisateurs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Nouvel utilisateur'), findsOneWidget);
    await back(tester);
    expect(find.text('Nouvel utilisateur'), findsNothing);
    expect(find.byType(ManageUsersScreen), findsOneWidget);
    expect(exits, 0);
  });

  testWidgets(
    'phone Back respects draft confirmation and dismisses its dialog first',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Gérer les utilisateurs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Brouillon à garder',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      await back(tester);
      expect(find.text('Abandonner les modifications ?'), findsOneWidget);
      await back(tester);
      expect(find.text('Abandonner les modifications ?'), findsNothing);
      expect(find.text('Brouillon à garder'), findsOneWidget);
      await back(tester);
      await tester.tap(find.text('Abandonner'));
      await tester.pumpAndSettle();
      expect(find.text('Nouvel utilisateur'), findsNothing);
      expect(find.byType(ManageUsersScreen), findsOneWidget);
      expect(exits, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Back restores previous tabs and their search without exiting', (
    tester,
  ) async {
    await open(tester, role: 'amina');
    await tester.tap(find.text('Chambres'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '305');
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();

    await back(tester);
    expect(find.widgetWithText(TextField, '305'), findsOneWidget);
    expect(find.text('Chaque chambre, en un regard.'), findsOneWidget);
    await back(tester);
    expect(find.text('12 chambres restantes'), findsOneWidget);
    expect(find.text(AppBackNavigation.exitMessage), findsNothing);
    expect(exits, 0);
  });

  testWidgets(
    'room detail Back returns to the selected tab before its history',
    (tester) async {
      await open(tester, role: 'amina');
      await tester.tap(find.text('Chambres'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '305');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chambre 305'));
      await tester.pumpAndSettle();
      expect(find.byType(DetailsScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(DetailsScreen), findsNothing);
      expect(find.widgetWithText(TextField, '305'), findsOneWidget);
      await back(tester);
      expect(find.text('12 chambres restantes'), findsOneWidget);
      expect(exits, 0);
    },
  );

  testWidgets('notifications and room details unwind in order', (tester) async {
    await open(tester, role: 'amina');
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);
    await tester.tap(find.text('Départ VIP'));
    await tester.pumpAndSettle();
    expect(find.byType(DetailsScreen), findsOneWidget);
    await back(tester);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    await back(tester);
    expect(find.byType(MainScreen), findsOneWidget);
    expect(find.text(AppBackNavigation.exitMessage), findsNothing);
    expect(exits, 0);
  });

  testWidgets('reselecting a tab does not create duplicate Back steps', (
    tester,
  ) async {
    await open(tester, role: 'sarah');
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('MON SERVICE · AGENT D’ÉTAGE'), findsOneWidget);
    await back(tester);
    expect(find.text(AppBackNavigation.exitMessage), findsOneWidget);
    expect(exits, 0);
  });

  testWidgets('login uses the same two-step exit protection', (tester) async {
    await open(tester, role: null);
    expect(find.byType(LoginScreen), findsOneWidget);
    await back(tester);
    expect(exits, 0);
    expect(find.text(AppBackNavigation.exitMessage), findsOneWidget);
    await back(tester);
    expect(exits, 1);
  });

  testWidgets('Back during saving cannot close the form or arm app exit', (
    tester,
  ) async {
    final auth = PendingCreateUsers();
    await open(tester, users: auth);
    await tester.tap(find.text('Gérer les utilisateurs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Nouvel agent');
    await tester.enterText(find.byType(TextFormField).at(1), 'new@nova.test');
    await tester.enterText(find.byType(TextFormField).at(2), 'password1');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Créer l’utilisateur');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Nouvel utilisateur'), findsOneWidget);
    expect(find.text(AppBackNavigation.exitMessage), findsNothing);
    expect(exits, 0);
    auth.saving.complete();
    await tester.pumpAndSettle();
    expect(find.text('Nouvel utilisateur'), findsNothing);
    expect(find.byType(ManageUsersScreen), findsOneWidget);
  });

  testWidgets(
    'logout clears session history and the pending exit confirmation',
    (tester) async {
      final auth = await open(tester);
      await back(tester);
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await back(tester);
      expect(exits, 0);
      expect(find.text(AppBackNavigation.exitMessage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('backgrounding cancels an armed exit confirmation', (
    tester,
  ) async {
    await open(tester);
    await back(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await back(tester);
    expect(exits, 0);
    expect(find.text(AppBackNavigation.exitMessage), findsOneWidget);
  });

  testWidgets('Back dismisses the keyboard before navigating away', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Gérer les utilisateurs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await back(tester);
    expect(find.byType(ManageUsersScreen), findsOneWidget);
    expect(find.text(AppBackNavigation.exitMessage), findsNothing);
    expect(exits, 0);
    tester.view.resetViewInsets();
    await tester.pump();
    await back(tester);
    expect(find.text('Espace manager'), findsOneWidget);
  });

  testWidgets('exit message fits a small phone with enlarged text', (
    tester,
  ) async {
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await open(tester);
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text(AppBackNavigation.exitMessage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(NovaParisApp),
      matchesGoldenFile('goldens/back_exit_large_text.png'),
    );
    debugDisableShadows = true;
  });

  testWidgets('standalone demo also returns through tab history before exit', (
    tester,
  ) async {
    final data = HotelData();
    addTearDown(data.dispose);
    await tester.pumpWidget(NovaParisApp(data: data));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chambres'));
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('12 chambres restantes'), findsOneWidget);
    expect(find.text(AppBackNavigation.exitMessage), findsNothing);
    expect(exits, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
