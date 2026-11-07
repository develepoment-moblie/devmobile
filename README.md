# Nova Paris

Application mobile de gestion hôtelière.

## Stack
- Flutter
- Supabase (auth + base de données)

## Rôles
- `guest` — client
- `staff` — personnel
- `manager` / `admin` — gestion des utilisateurs
- `maintenance` — interventions

## Module Maintenance
- Accès : carte **Maintenance** (Accès rapide du personnel) ou accueil du rôle `maintenance`.
- Écrans : `lib/screens/maintenance/` (liste, signalement, détail, historique).
- Backend : tables SQLite `interventions` et `intervention_photos`
  (`services/maintenance_schema.dart`) + `services/maintenance_service.dart`.
- Comptes de démo (rôle `maintenance`, mot de passe `maintenance1234!`) :
  `thomas@novaparis.com`, `marc@novaparis.com`.
