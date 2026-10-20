# Module Chambres et ménage

Responsable : **jassernoomani** · Dossier : `lib/housekeeping/` · Tests : `test/housekeeping/`

Statut des chambres, attribution, validation, linge et produits.

## Fonctionnalités (cahier des charges)

- [ ] Statut des chambres
- [ ] Attribution des tâches
- [ ] Notification au départ du client
- [ ] Validation par la gouvernante
- [ ] Linge et produits d’entretien

## Structure

- `housekeeping_module.dart` : point d’entrée (titre, rôles, tables, premier écran).
- `models/` : classes de données.
- `custom/` : widgets réutilisables du module.
- `screens/` : écrans. `housekeeping_home_screen.dart` est le premier écran.
- `services/` : accès à la base SQLite et logique métier.

Tables SQLite : préfixe obligatoire `housekeeping_` (voir CONTRIBUTING.md).
