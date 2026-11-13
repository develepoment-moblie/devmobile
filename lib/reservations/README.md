# Module Réservations

Responsable : **à compléter** · Dossier : `lib/reservations/` · Tests : `test/reservations/`

Réservations, disponibilités, tarifs, check-in et check-out.

## Fonctionnalités (cahier des charges)

- [ ] Création, modification et annulation
- [ ] Calendrier de disponibilité
- [ ] Tarifs, saisons et promotions
- [ ] Check-in et check-out
- [ ] Fiche client et historique

## Structure

- `reservations_module.dart` : point d’entrée (titre, rôles, tables, premier écran).
- `models/` : classes de données.
- `custom/` : widgets réutilisables du module.
- `screens/` : écrans. `reservations_home_screen.dart` est le premier écran.
- `services/` : accès à la base SQLite et logique métier.

Tables SQLite : préfixe obligatoire `reservations_` (voir CONTRIBUTING.md).

## Recherche externe dans Android Studio

Pour activer la recherche StayingAPI, créez `.staying.local.json` à la racine du projet avec votre clé de test. Git ignore ce fichier.

```json
{"STAYING_API_KEY": "VOTRE_CLE_STAYINGAPI"}
```

Arrêtez et relancez l’application avec la configuration Flutter habituelle. Le build Android debug lit ce fichier automatiquement. Un argument `--dart-define-from-file=.staying.local.json` reste possible et prend la priorité.
