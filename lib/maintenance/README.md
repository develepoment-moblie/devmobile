# Module Maintenance

Responsable : **à compléter** · Dossier : `lib/maintenance/` · Tests : `test/maintenance/`

Signalements avec photo, interventions, urgences et historique.

## Fonctionnalités (cahier des charges)

- [ ] Signalement avec photo
- [ ] Attribution et suivi (en attente, en cours, résolu)
- [ ] Priorisation des urgences
- [ ] Historique par chambre
- [ ] Maintenance préventive

## Structure

- `maintenance_module.dart` : point d’entrée (titre, rôles, tables, premier écran).
- `models/` : classes de données.
- `custom/` : widgets réutilisables du module.
- `screens/` : écrans. `maintenance_home_screen.dart` est le premier écran.
- `services/` : accès à la base SQLite et logique métier.

Tables SQLite : préfixe obligatoire `maintenance_` (voir CONTRIBUTING.md).
