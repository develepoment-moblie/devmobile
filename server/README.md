# Serveur de synchronisation Nova Paris

Petit service web REST (Dart, `shelf`, SQLite) qui partage le travail du module
« Chambres et ménage » entre les téléphones de l'hôtel. Il tient un journal
numéroté des actions reçues ; les règles métier restent dans l'application, qui
rejoue les actions des autres téléphones (voir `lib/housekeeping/README.md`).

## Lancer

```sh
cd server
dart pub get
dart run bin/server.dart            # port 8080, journal data/nova_sync.db
dart run bin/server.dart --port 9000 --db data/autre.db
```

Le serveur affiche les adresses à saisir dans l'application (écran
« Synchronisation »), par exemple `192.168.1.11:8080`. Le téléphone doit être
sur le même Wi-Fi que l'ordinateur ; depuis l'émulateur Android : `10.0.2.2:8080`.
Pare-feu Windows : autoriser Dart sur les réseaux privés au premier lancement.

## API

| Méthode | Chemin | Rôle |
|---|---|---|
| GET | `/v1/health` | serveur en marche, nombre d'actions |
| POST | `/v1/sync/push` | `{deviceId, mutations:[{mutationId, path, body, actorId, appliedAt}]}` → `applied`, `duplicate` ou `rejected` pour chacune |
| GET | `/v1/sync/pull?since=<seq>&limit=50` | toutes les actions après `since`, dans l'ordre du serveur, celles du téléphone qui demande comprises ; `until` = dernier numéro rendu, `more` = page suivante |
| GET | `/v1/rooms/activity` | dernière action de chaque chambre (à ouvrir dans un navigateur) |

Un `mutationId` déjà reçu n'est jamais enregistré deux fois : un téléphone
peut toujours renvoyer après une coupure.

L'ordre du serveur fait foi : chaque téléphone reconstruit ses données en
appliquant cette liste dans l'ordre (ses propres actions comprises), puis
ses actions pas encore numérotées par-dessus. Une action refusée par les
règles l'est donc sur tous les téléphones.

## Tests

```sh
dart test
```
