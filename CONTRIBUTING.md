# Travailler ensemble sans conflits

## La règle d’or

**Chacun ne modifie que son dossier** `lib/<module>/` et `test/<module>/`.
Tous les modules sont déjà branchés dans l’application (`lib/app/modules.dart`) :
vous n’avez pas besoin de toucher à `lib/app/`.

Un test (`test/app/app_shell_test.dart`) vérifie automatiquement qu’aucun module
n’importe le dossier d’un autre module ni `lib/app/`.

## Démarrer sur son module

```bash
git checkout main
git pull
git checkout -b <module>        # ex. reservations, maintenance, billing…
```

Puis travaillez dans `lib/<module>/` :

1. Remplacez le contenu de `screens/<module>_home_screen.dart` par votre premier écran.
2. Ajoutez vos classes dans `models/`, vos widgets dans `custom/`, votre accès aux
   données dans `services/`.
3. Si besoin, changez les rôles qui voient votre module dans `<module>_module.dart`.

Conventions du cours : `setState`, `Form`, `TextFormField`, `Navigator`.
Un seul `MaterialApp` (celui de `lib/app/`) : vos écrans sont des `Scaffold`.

## Ce que chaque écran reçoit : `AppSession`

```dart
session.user            // AppUser : id, fullName, role (null si déconnecté)
session.database        // AppDatabase : la base SQLite commune
session.events          // AppEvents : messages entre modules
```

## Base de données : vos propres tables

Une seule base `nova_paris.db`, mais **chaque module a ses tables et son propre
numéro de version**. Préfixez toujours vos tables par le nom du module.

```dart
@override
ModuleSchema get schema => ModuleSchema(
  module: id,
  version: 2, // +1 à chaque changement de vos tables
  migrate: (tx, from, to) async {
    if (from < 1) {
      await tx.execute('''CREATE TABLE reservations_bookings (
        id TEXT PRIMARY KEY, room_number TEXT NOT NULL,
        guest_name TEXT NOT NULL, arrival TEXT NOT NULL, departure TEXT NOT NULL)''');
    }
    if (from < 2) {
      await tx.execute(
        "ALTER TABLE reservations_bookings ADD COLUMN status TEXT NOT NULL DEFAULT 'confirmed'",
      );
    }
  },
);
```

- Ne modifiez jamais une étape déjà poussée : ajoutez-en une nouvelle (`from < 3`…).
- Lecture/écriture : `session.database.database.query('reservations_bookings')`.
- Pour lire les données d’un autre module, demandez-lui un événement ou une
  méthode dans `lib/shared/` ; ne lisez pas ses tables directement.
- Mots de passe : jamais en clair (hachage avec sel).

## Communiquer entre modules : les événements

Définis dans `lib/shared/services/app_events.dart` :

| Événement | Émis par | Écouté par |
|---|---|---|
| `GuestCheckedIn(chambre, guestName:)` | Réservations | Ménage, Facturation |
| `GuestCheckedOut(chambre)` | Réservations | Ménage |
| `RoomReady(chambre)` | Ménage | Réservations |
| `MaintenanceRequested(chambre, description:, urgent:)` | tous | Maintenance |
| `MaintenanceResolved(chambre)` | Maintenance | Ménage, Réservations |
| `ExtraCharged(chambre, label:, amountCents:)` | Services clients | Facturation |

```dart
session.events.emit(const GuestCheckedOut('305'));
session.events.on<GuestCheckedOut>().listen((e) => /* chambre e.roomNumber */);
```

Ajouter un événement : OK, signalez-le dans votre pull request.
Modifier ou supprimer un événement existant : à décider en équipe.

## Fichiers partagés : prévenir l’équipe

`pubspec.yaml`, `lib/shared/`, `lib/app/`, `AndroidManifest.xml`. Si vous devez les
modifier (ajout d’un package, d’une permission caméra…), faites une petite pull
request séparée et prévenez le groupe.

## Envoyer son travail

```bash
flutter analyze
flutter test
git add lib/<module> test/<module>
git commit -m "<module>: description courte"
git push -u origin <module>
```

Puis ouvrez une **pull request vers `main`** sur GitHub. Avant de la fusionner :
`flutter analyze` sans erreur et `flutter test` réussi.

Récupérer le travail des autres pendant que vous avancez :

```bash
git checkout <module>
git pull origin main
```

## Le module Utilisateurs

`lib/user_management/screens/login_screen.dart` est une connexion de test (nom +
rôle, sans mot de passe). Le responsable du module la remplace par la vraie
connexion en gardant le même appel : `session.signIn(AppUser(...))`.
Les rôles partagés sont dans `lib/shared/models/app_user.dart` (`AppRole`).
