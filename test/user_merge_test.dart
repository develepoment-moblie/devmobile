import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/main.dart';
import 'package:nova_paris/shared/custom/app_theme.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_backend.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_api.dart';
import 'package:nova_paris/user_management/models/app_user.dart';
import 'package:nova_paris/user_management/services/user_repository.dart';
import 'package:nova_paris/user_management/screens/login_screen.dart';
import 'package:nova_paris/user_management/screens/manage_users.dart';

class FakeUsers implements UserRepository {
  final changes = StreamController<void>.broadcast();
  final users = <AppUser>[
    const AppUser(id: 'manager', fullName: 'Alex Martin', role: 'manager'),
    const AppUser(
      id: 'amina',
      fullName: 'Amina Gouvernante',
      role: 'supervisor',
    ),
    const AppUser(id: 'sarah', fullName: 'Sarah Agent', role: 'staff'),
  ];
  String? active;
  bool failCreate = false, failLogin = false, failProfile = false;
  int signups = 0, creates = 0;
  Completer<AppUser>? pendingProfile;
  @override
  String? get sessionUserId => active;
  @override
  Stream<void> get sessionChanges => changes.stream;
  @override
  Future<void> login(String email, String password) async {
    if (failLogin) {
      throw const HousekeepingException(
        'Connexion refusée. Vérifiez les informations saisies.',
      );
    }
    active = 'sarah';
    changes.add(null);
  }

  @override
  Future<void> register(String email, String password, String name) async {
    signups++;
    users.add(
      const AppUser(id: 'guest', fullName: 'Nouveau Client', role: 'guest'),
    );
    active = 'guest';
    changes.add(null);
  }

  @override
  Future<void> logout() async {
    active = null;
    changes.add(null);
  }

  @override
  Future<AppUser> currentProfile() async {
    if (pendingProfile != null) return pendingProfile!.future;
    if (failProfile) {
      throw const HousekeepingException('Profil indisponible.', 403);
    }
    return users.firstWhere((u) => u.id == active);
  }

  @override
  Future<List<AppUser>> allProfiles() async => List.of(users);
  @override
  Future<void> updateUser(AppUser original, String name, String role) async {
    final i = users.indexWhere((u) => u.id == original.id);
    users[i] = AppUser(
      id: original.id,
      fullName: name,
      role: role,
      revision: original.revision + 1,
    );
  }

  @override
  Future<void> createUser(
    String email,
    String password,
    String name,
    String role,
  ) async {
    creates++;
    if (failCreate) {
      throw const HousekeepingException('Création non confirmée.');
    }
    users.add(AppUser(id: 'new', fullName: name, role: role));
  }

  @override
  Future<void> deleteProfile(AppUser original) async {
    users.removeWhere((u) => u.id == original.id);
  }
}

class FakeHousekeeping implements HousekeepingBackend {
  final FakeUsers auth;
  FakeHousekeeping(this.auth);
  @override
  Future<Map<String, dynamic>> snapshot() async {
    final s = jsonDecode(
      File('test/fixtures/snapshot.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final user = await auth.currentProfile();
    s['principal'] = {
      'id': user.id,
      'name': user.fullName,
      'role': user.role == 'supervisor' ? 'supervisor' : 'agent',
    };
    return s;
  }

  @override
  Future<void> mutate(String path, Map<String, dynamic> body) async {}
  @override
  void close() {}
}

void main() {
  Future<void> app(
    WidgetTester tester,
    FakeUsers auth, {
    double width = 402,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 874);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(auth.changes.close);
    await tester.pumpWidget(
      NovaParisApp(
        auth: auth,
        housekeepingFactory: () => FakeHousekeeping(auth),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('User model preserves roles, stable identity and profile versions', () {
    final user = AppUser.fromMap({
      'id': 'id',
      'full_name': '  Sarah   Noomani',
      'role': 'staff',
      'points': 12,
      'revision': 3,
    });
    expect(user.firstName, 'Sarah');
    expect(user.canUseHousekeeping, true);
    expect(user.canManageUsers, false);
    expect(user.revision, 3);
    expect(
      const AppUser(id: 'id', fullName: 'Amina', role: 'supervisor').roleLabel,
      'Gouvernante',
    );
  });
  testWidgets('Login validates email and keeps it after a failed sign-in', (
    tester,
  ) async {
    final auth = FakeUsers()..failLogin = true;
    await app(tester, auth);
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(find.text('Renseignez un e-mail valide.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'sarah@example.com',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'not-a-real-password',
    );
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(find.text('sarah@example.com'), findsOneWidget);
    expect(
      find.text('Connexion refusée. Vérifiez les informations saisies.'),
      findsOneWidget,
    );
    expect(
      (tester.widget<TextFormField>(find.byType(TextFormField).at(1)))
          .controller!
          .text,
      isEmpty,
    );
  });
  testWidgets('Local signup opens the guest session immediately', (
    tester,
  ) async {
    final auth = FakeUsers();
    await app(tester, auth);
    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Nouveau Client');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'guest@example.com',
    );
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'temporary-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Créer un compte'));
    await tester.pumpAndSettle();
    expect(auth.signups, 1);
    expect(auth.active, 'guest');
    expect(find.text('BONJOUR NOUVEAU'), findsOneWidget);
  });
  testWidgets(
    'Staff login opens housekeeping and authenticated profile without role switch',
    (tester) async {
      final auth = FakeUsers();
      await app(tester, auth);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'sarah@example.com',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'temporary-password',
      );
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();
      expect(find.text('MON SERVICE · AGENT D’ÉTAGE'), findsOneWidget);
      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      expect(find.text('Sarah Agent'), findsOneWidget);
      expect(find.text('AGENT D’ÉTAGE'), findsOneWidget);
      expect(find.text('Rôle de démonstration'), findsNothing);
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    },
  );
  testWidgets('Gouvernante session enables attribution from the actual role', (
    tester,
  ) async {
    final auth = FakeUsers()..active = 'amina';
    await app(tester, auth);
    await tester.tap(find.text('Attribuer une tâche'));
    await tester.pumpAndSettle();
    expect(find.text('Attribuer la tâche'), findsOneWidget);
  });
  testWidgets(
    'Logout disposes pushed management routes and cannot return to them',
    (tester) async {
      final auth = FakeUsers()..active = 'manager';
      await app(tester, auth);
      await tester.tap(find.text('Gérer les utilisateurs'));
      await tester.pumpAndSettle();
      expect(find.byType(ManageUsersScreen), findsOneWidget);
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ManageUsersScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Late profile response after logout cannot restore a privileged route',
    (tester) async {
      final auth = FakeUsers()
        ..active = 'manager'
        ..pendingProfile = Completer<AppUser>();
      await tester.pumpWidget(
        NovaParisApp(
          auth: auth,
          housekeepingFactory: () => FakeHousekeeping(auth),
        ),
      );
      await tester.pump();
      await auth.logout();
      await tester.pump();
      auth.pendingProfile!.complete(auth.users.first);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Gérer les utilisateurs'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await auth.changes.close();
    },
  );
  testWidgets('Role revocation replaces an open management route', (
    tester,
  ) async {
    final auth = FakeUsers()..active = 'manager';
    await app(tester, auth);
    await tester.tap(find.text('Gérer les utilisateurs'));
    await tester.pumpAndSettle();
    auth.users[0] = const AppUser(
      id: 'manager',
      fullName: 'Alex Martin',
      role: 'maintenance',
      revision: 2,
    );
    auth.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(ManageUsersScreen), findsNothing);
    expect(find.text('Maintenance'), findsOneWidget);
  });
  testWidgets(
    'Profile failure is recoverable and never falls back to a guest account',
    (tester) async {
      final auth = FakeUsers()
        ..active = 'manager'
        ..failProfile = true;
      await app(tester, auth);
      expect(find.text('Profil indisponible.'), findsOneWidget);
      expect(find.text('Gérer les utilisateurs'), findsNothing);
      auth.failProfile = false;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Gérer les utilisateurs'), findsOneWidget);
    },
  );
  testWidgets(
    'User creation failure keeps inputs; success preserves manager identity',
    (tester) async {
      final auth = FakeUsers()
        ..active = 'manager'
        ..failCreate = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: novaTheme(),
          home: ManageUsersScreen(auth: auth),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Nouvel Agent');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'agent@example.com',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'temporary-password',
      );
      await tester.ensureVisible(find.text('Créer l’utilisateur'));
      await tester.tap(find.text('Créer l’utilisateur'));
      await tester.pumpAndSettle();
      expect(find.byType(UserFormSheet), findsOneWidget);
      expect(find.text('Création non confirmée.'), findsOneWidget);
      expect(find.text('Nouvel Agent'), findsOneWidget);
      expect(auth.active, 'manager');
      auth.failCreate = false;
      await tester.tap(find.text('Créer l’utilisateur'));
      await tester.pumpAndSettle();
      expect(find.byType(UserFormSheet), findsNothing);
      expect(find.text('Nouvel Agent'), findsOneWidget);
      expect(auth.active, 'manager');
      await tester.pumpWidget(const SizedBox());
      await auth.changes.close();
    },
  );
  testWidgets('User list supports clearing a no-results search', (
    tester,
  ) async {
    final auth = FakeUsers()..active = 'manager';
    await app(tester, auth);
    await tester.tap(find.text('Gérer les utilisateurs'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nobody');
    await tester.pumpAndSettle();
    expect(find.text('Aucun utilisateur trouvé'), findsOneWidget);
    await tester.tap(find.byTooltip('Effacer la recherche'));
    await tester.pumpAndSettle();
    expect(find.text('Amina Gouvernante'), findsOneWidget);
  });
  testWidgets('Guest landing from the user module fits a small phone', (
    tester,
  ) async {
    final auth = FakeUsers()..active = 'guest';
    auth.users.add(
      const AppUser(id: 'guest', fullName: 'Client Invité', role: 'guest'),
    );
    await app(tester, auth, width: 320);
    expect(find.text('BONJOUR CLIENT'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Rechercher'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Small phone and enlarged text keep login usable', (
    tester,
  ) async {
    final auth = FakeUsers();
    await app(tester, auth, width: 320, scale: 2);
    await tester.ensureVisible(find.text('Se connecter'));
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
