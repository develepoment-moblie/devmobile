# Module Facturation et rapports

Responsable : **à compléter** · Dossier : `lib/billing/` · Tests : `test/billing/`

Factures, paiements, tableau de bord et exports.

## Fonctionnalités (cahier des charges)

- [ ] Factures et paiements
- [ ] Tableau de bord (occupation, CA, RevPAR)
- [ ] Rapports journaliers, hebdomadaires, mensuels
- [ ] Export PDF ou Excel

## Structure

- `billing_module.dart` : point d’entrée (titre, rôles, tables, premier écran).
- `models/` : classes de données.
- `custom/` : widgets réutilisables du module.
- `screens/` : écrans. `billing_home_screen.dart` est le premier écran.
- `services/` : accès à la base SQLite et logique métier.

Tables SQLite : préfixe obligatoire `billing_` (voir CONTRIBUTING.md).
