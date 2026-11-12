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

### Fonctions avancées de la maintenance
- **Maintenance prédictive (Open-Meteo, gratuit, sans clé)** : à l'ouverture de l'écran
  Maintenance (au plus toutes les 3 h), les prévisions à 3 jours créent des interventions
  préventives (canicule → climatisations, gel → chauffage, orage/pluie → fuites, vent →
  fenêtres). Test sans attendre la météo : `flutter run --dart-define=WEATHER_DEMO=true`.
- **Diagnostic IA par photo (API Claude)** : la 1re photo d'un signalement pré-remplit titre,
  description, catégorie et priorité. Désactivé tant que la clé n'est pas fournie :
  `flutter run --dart-define=AI_API_KEY=sk-ant-...` (ne jamais la mettre dans le code ni sur Git).
  En production, utilisez un serveur intermédiaire : `--dart-define=AI_BASE_URL=https://...`.
