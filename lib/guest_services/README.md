# Module Services clients

Responsable : **à compléter** · Dossier : `lib/guest_services/` · Tests : `test/guest_services/`

Room service, restaurant, spa, demandes spéciales et messagerie.

## Fonctionnalités (cahier des charges)

- [ ] Room service, restaurant et spa
- [ ] Demandes spéciales
- [ ] Messagerie client ↔ réception
- [ ] Plaintes et avis
- [ ] Extras sur la note de chambre

## Structure

- `guest_services_module.dart` : point d’entrée (titre, rôles, tables, premier écran).
- `models/` : classes de données.
- `custom/` : widgets réutilisables du module.
- `screens/` : écrans. `guest_services_home_screen.dart` est le premier écran.
- `services/` : accès à la base SQLite et logique métier.

Tables SQLite : préfixe obligatoire `guest_services_` (voir CONTRIBUTING.md).
