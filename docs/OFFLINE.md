# Fonctionnement hors ligne

L'application normale fonctionne hors ligne avec SQLite. Lire SQLITE.md pour
les comptes initiaux, la persistance et les limites. Les données restent sur
l'appareil, sans synchronisation. L'inscription locale connecte un nouveau client
immédiatement ; le Manager crée les comptes du personnel.

## Anciennes démonstrations isolées

- `--dart-define=LOCAL_JSON_DEMO=true` ouvre l'ancienne démo persistante JSON via
  shared_preferences, signalée par le bandeau « Démo hors ligne ».
- `--dart-define=HOUSEKEEPING_DEMO=true` ouvre la démonstration ménage en mémoire.
- Les paramètres HOUSEKEEPING_API_URL / HOUSEKEEPING_TOKEN sélectionnent
  l'ancienne API Node/SQLite ; voir backend/README.md.

Retirer ces paramètres dans Android Studio pour utiliser SQLite par défaut.
La démo JSON possède ses propres données ; aucun import automatique.
Les comptes fictifs ont le mot de passe `Nova123!`, avec les mêmes adresses
@nova.test que les exemples SQLite. Ne pas y utiliser de données sensibles.
