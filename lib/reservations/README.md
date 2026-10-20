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
