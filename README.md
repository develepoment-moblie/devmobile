# Nova Paris

Application mobile Flutter de gestion hôtelière, projet d’équipe.
Ce dépôt (branche `main`) est le **squelette commun** : chaque membre ajoute son
module dans son propre dossier, ce qui permet de tout fusionner sans conflit.

## Lancer l’application

```powershell
flutter pub get
flutter run
```

L’écran de connexion est **temporaire** : saisissez un nom et choisissez un rôle
pour voir les modules de ce rôle. Le module Utilisateurs le remplacera par la
vraie connexion.

```powershell
flutter analyze
flutter test
```

## Modules

| Module | Dossier | Responsable | Rôles qui le voient |
|---|---|---|---|
| Réservations | `lib/reservations/` | à compléter | Réception, Manager, Admin, Client |
| Chambres et ménage | `lib/housekeeping/` | jassernoomani | Agent, Gouvernante, Manager, Admin |
| Maintenance | `lib/maintenance/` | à compléter | Technicien, Agent, Gouvernante, Réception, Manager, Admin |
| Services clients | `lib/guest_services/` | à compléter | Client, Réception, Manager, Admin |
| Facturation et rapports | `lib/billing/` | à compléter | Réception, Manager, Admin |
| Utilisateurs | `lib/user_management/` | Skander256 | Manager, Admin (+ connexion et profil pour tous) |

Chaque dossier contient un `README.md` avec les fonctionnalités du cahier des charges.

## Structure

```text
lib/
  main.dart              ouvre la base SQLite et lance l’application
  app/                   coquille commune : MaterialApp, accueil, liste des modules
  shared/                commun à tous : thème, widgets, AppUser, rôles,
                         base de données, session, événements entre modules
  <module>/              un dossier par module :
    <module>_module.dart   point d’entrée (titre, rôles, tables, 1er écran)
    models/ custom/ screens/ services/
test/
  app/                   tests de la coquille et des règles d’architecture
  <module>/              tests de chaque module
```

Avant de commencer, lisez [CONTRIBUTING.md](CONTRIBUTING.md).

## Charte graphique

Couleurs dans `lib/shared/custom/app_theme.dart` (vert `#183C35`, accent
`#C66F55`), police Manrope, logo `assets/images/nova_paris_logo.png`.
