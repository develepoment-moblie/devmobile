# Module Maintenance

Responsable : **Ayoub Belgacem** · Dossier : `lib/maintenance/` · Tests : `test/maintenance/`

Signalements avec photo, interventions, urgences et historique.

## Fonctionnalités (cahier des charges)

- [x] Signalement avec photo
- [x] Attribution et suivi (en attente, en cours, résolu)
- [x] Priorisation des urgences
- [ ] Historique par chambre
- [ ] Maintenance préventive

## Structure

- `maintenance_module.dart` : point d’entrée (titre, rôles, tables, premier écran).
- `models/` : classes de données.
- `custom/` : widgets réutilisables du module.
- `screens/` : écrans. `maintenance_home_screen.dart` est le premier écran.
- `services/` : accès à la base SQLite et logique métier.

Tables SQLite : préfixe obligatoire `maintenance_` (voir CONTRIBUTING.md).

## Fonctions avancées

- **Maintenance prédictive (Open-Meteo, gratuit, sans clé)** : à l'ouverture de l'écran
  Maintenance (au plus toutes les 3 h), les prévisions à 3 jours créent des interventions
  préventives « Tout l'hôtel » (chaleur ≥ 30 °C → climatisations, gel → chauffage,
  orage/pluie → fuites, vent → fenêtres), sans doublon tant qu'une alerte du même type est
  ouverte ou résolue depuis moins de 48 h. Démonstration : `--dart-define=WEATHER_DEMO=true`.
- **Diagnostic IA par photo (API Claude)** : la 1re photo d'un signalement pré-remplit titre,
  description, catégorie et priorité. Désactivé tant que la clé n'est pas fournie :
  `--dart-define=AI_API_KEY=sk-ant-...` (jamais dans le code ni sur Git). En production,
  passez par un serveur intermédiaire : `--dart-define=AI_BASE_URL=https://...`.
- **Traduction** de la description en anglais (MyMemory, gratuit, sans clé).
