# Backend du module chambres et ménage

Le lancement normal utilise SQLite sur le téléphone pour les deux modules.
Ce dossier conserve l'ancienne API Node/SQLite de démonstration du ménage.
Voir ../SQLITE.md pour l'application fusionnée locale.

API Node.js 24+ et SQLite, sans dépendances npm. Le fichier de base est sur le
serveur : les téléphones qui utilisent ce serveur partagent les mêmes données.
Le serveur doit rester démarré. Les données sont conservées après son redémarrage.
Il n'y a pas de service cloud déployé automatiquement.

## Premier lancement sur ce PC

Dans le terminal PowerShell d'IntelliJ, à la racine `E:\DevMobile\nova_paris` :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\backend\setup-dev.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\backend\start-dev.ps1
```

Garder ce terminal ouvert. Le script utilise Node 24+ installé ou, sur ce PC,
le runtime Node 24 fourni avec Codex. Le Node système actuel est en version 22.
Sur un autre PC, installer Node 24+ puis utiliser les mêmes scripts ou `node`.
Le premier script ne réinitialise pas les modifications existantes.
Il renouvelle les identités de test pour 24 heures : Amina (gouvernante), Sarah,
Lina et Youssef (agents). Aucun écran de connexion ou gestion de comptes n'est ajouté.

## Téléphone Android par USB

Dans un **deuxième terminal**, connecter le téléphone avec débogage USB autorisé.
Utiliser `adb` du SDK Android. Sur ce PC, `android/local.properties` indique `C:\android-sdk` :

```powershell
& 'C:\android-sdk\platform-tools\adb.exe' -s uwvc4p59vgqceajr reverse tcp:8086 tcp:8086
C:\flutter\bin\flutter.bat run -d uwvc4p59vgqceajr --dart-define-from-file=backend/.dev/amina.json
```

Si le SDK Android est ailleurs, récupérer son chemin dans `android/local.properties`
(`sdk.dir`) et utiliser son dossier `platform-tools`. Pour tester Sarah, remplacer
`amina.json` par `sarah.json`. Chaque lancement connecté utilise une identité fixe ;
le choix de rôle du Profil est réservé au mode local.

Dans **Run > Edit Configurations > Flutter > Additional run args**, mettre :

```text
--dart-define-from-file=backend/.dev/amina.json
```

Relancer complètement après un changement de fichier de configuration ; un hot reload
ne change pas les paramètres de compilation. Sans ces paramètres, le lancement
reste la démonstration locale en mémoire.

Si la compilation en terminal affiche `Unable to establish loopback connection`
avec Java sur ce PC, le build a été vérifié avec ces variables limitées au terminal :

```powershell
New-Item -ItemType Directory -Force build/java-tmp | Out-Null
$env:JAVA_TOOL_OPTIONS='-Djdk.net.unixdomain.tmpdir=E:\DevMobile\nova_paris\build\java-tmp'
$env:GRADLE_OPTS='-Dorg.gradle.daemon=false'
C:\flutter\bin\flutter.bat build apk --debug --dart-define-from-file=backend/.dev/amina.json
```

Le dernier APK debug compilé contient la session de test Amina, valable 24 heures
après setup. Il utilise le serveur 127.0.0.1:8086 et nécessite donc `adb reverse`
sur le téléphone. Ce build n'a pas été installé automatiquement sur le téléphone.

## Deux téléphones

Option USB : connecter les deux téléphones au PC, exécuter `adb -s ID reverse
tcp:8086 tcp:8086` pour chacun, puis lancer Amina sur l'un et Sarah sur l'autre.
Les deux fichiers conservent `http://127.0.0.1:8086` grâce à la redirection USB.

Option Wi-Fi local : définir `$env:HOST='0.0.0.0'` avant de démarrer le serveur,
remplacer `HOUSEKEEPING_API_URL` dans chaque fichier privé par l'adresse IPv4
du PC (exemple `http://192.168.1.20:8086`), et utiliser le même réseau. Autoriser
le port 8086 seulement sur le réseau privé si le pare-feu Windows le demande.
Le code ne modifie pas le pare-feu. HTTP est activé uniquement dans le manifeste
Android debug. Ne pas exposer ce serveur de développement à Internet.

Pour le navigateur, utiliser `flutter run -d chrome --web-port=8085
--dart-define-from-file=backend/.dev/amina.json`. Les origines locales 8085 sont
autorisées par `start-dev.ps1`. Les autres origines doivent être configurées
explicitement dans `CORS_ORIGINS` (séparées par une virgule).

## Permissions réellement appliquées

| Action | Gouvernante | Agent |
|---|---|---|
| Consulter chambres, tâches et stock | Oui | Oui |
| Attribuer / réattribuer une tâche | Oui | Non |
| Démarrer, cocher, terminer un nettoyage | Non | Sa propre tâche uniquement |
| Valider un nettoyage | Oui | Non |
| Modifier le linge et les produits | Oui | Non |
| Marquer une notification lue | Ses notifications | Ses notifications |
| Transmettre un départ | Service réservations autorisé uniquement | Non |

La réattribution à un autre agent remet la tâche en attente et efface les contrôles.
Une tâche envoyée en validation ne peut plus être modifiée par l'agent.
Le statut « libre » n'est appliqué qu'après validation de la gouvernante.

## Contrat HTTP

Toutes les routes exigent `Authorization: Bearer JWT`. Les POST exigent JSON,
`Idempotency-Key` (16 à 100 caractères alphanumériques, tirets ou underscores),
et `version` correspondant à la ressource affichée, sauf les notifications.

| Méthode et route | Corps |
|---|---|
| GET `/v1/snapshot` | État du module, principal, agents et notifications visibles |
| POST `/v1/rooms/305/assign` | `{version, employeeId, note, urgent}` |
| POST `/v1/rooms/305/start` | `{version}` |
| POST `/v1/rooms/305/checklist` | `{version, index: 0..3, value: true/false}` |
| POST `/v1/rooms/305/submit` | `{version}` |
| POST `/v1/rooms/305/approve` | `{version}` |
| POST `/v1/rooms/112/checkout` | `{version}`, identité de service seulement |
| POST `/v1/supplies/sheets/movement` | `{version, delta: entier signé non nul}` |
| POST `/v1/notifications/read` | `{ids: [identifiants visibles]}` |

Réponse POST : `{ok:true}`, puis relecture du snapshot par le client. Erreurs :
400 données invalides, 401 session invalide, 403 permission refusée, 404 objet
introuvable, 409 conflit / transition interdite, 413 taille excessive, 415 format.
Le client attend la confirmation avant d'afficher le succès. Un conflit recharge
les valeurs serveur et conserve les notes du formulaire pour vérification.
La synchronisation de la coquille de démonstration relit le serveur toutes les
5 secondes ; aucun mécanisme de notifications push ou d'écriture hors connexion.

## Raccordement à la gestion utilisateur

Le serveur vérifie RS256 avec une clé publique configurée et contrôle `iss`,
`aud`, `exp`, `iat`, `nbf` éventuel, `sub` et `hotel_id`. Il ignore les rôles envoyés
par les widgets, les en-têtes X-Role ou le corps JSON. L'identifiant utilisateur et
l'hôtel signés doivent correspondre au personnel autorisé du serveur. Les rôles
proviennent actuellement de `state.staff`, provisionné côté serveur (fixtures de
développement), jamais d'une route mobile d'édition de rôles.

Lors de la fusion, utiliser la clé publique, l'issuer et l'audience de l'authentification
du groupe, remplacer le roster de démonstration par la source serveur du module
utilisateur, et conserver les vérifications de permissions dans `Store.principal`
et `Store.mutate`. Une révocation / un changement de rôle doit actualiser cette
source serveur. Le module ne délivre pas de sessions de production.

Pour les départs, le backend réservations transmet une identité de service signée,
avec un `sub` dédié absent du roster et `scope: 'housekeeping:checkout'`. Ne jamais
distribuer ce jeton aux téléphones. Il n'a pas accès au snapshot du personnel.

Variables serveur : `JWT_PUBLIC_KEY` (fichier PEM), `JWT_ISSUER`, `JWT_AUDIENCE`,
`DB_PATH` (défaut `data/housekeeping.sqlite`), `HOST` (127.0.0.1), `PORT` (8086),
`CORS_ORIGINS`. Le serveur démarre sans créer de comptes ou de fixtures automatiquement.
`dev-setup.mjs` est un outil de démonstration séparé, à ne pas utiliser pour des comptes réels.

## Conservation et déploiement

`data/` contient SQLite ; `.dev/` contient clés et sessions de test. Tous deux sont
ignorés par Git. Ne jamais partager `.dev/`, les fichiers de clés, les JWT ou un APK
de test contenant une session. Les paramètres `--dart-define-from-file` servent aux
essais : en production, fournir `tokenProvider` depuis le module utilisateur.

Les tables SQLite contiennent l'état du module par hôtel, les lectures par utilisateur,
les clés d'idempotence et un audit des mutations (acteur, action, objet, date UTC,
détails). Les transactions sérialisent les écritures. Une version périmée retourne
409. Une répétition de la même opération avec la même clé ne débite pas deux fois
le stock. Conserver les clés d'idempotence tant que les clients peuvent réessayer.
L'état JSON par hôtel vise ce projet pédagogique ; un schéma relationnel détaillé
pourra être adopté si le volume et les requêtes du groupe le nécessitent.

Pour sauvegarder, arrêter le serveur puis copier le fichier SQLite avec ses éventuels
fichiers `-wal` / `-shm`, ou utiliser une sauvegarde SQLite cohérente. Ne pas supprimer
le dossier `data` lors d'une mise à jour. Pour un service réellement disponible hors
du PC : hébergement durable, HTTPS, sauvegardes, vraie source d'identités et gestion
des clés restent à configurer. Le client Flutter release exige une URL HTTPS.

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\backend\test.ps1
C:\flutter\bin\flutter.bat test
```

Le test Flutter qui utilise un vrai serveur est facultatif dans la suite normale.
Pour l'exécuter, lancer dans un terminal (depuis `backend`) :

```powershell
. .\node-runtime.ps1
& $script:NodeRuntime test/bridge-server.mjs
```

Puis, à la racine du projet, dans un autre terminal :

```powershell
C:\flutter\bin\flutter.bat test test/live_backend_test.dart --dart-define=LIVE_HOUSEKEEPING_TEST=true
```

Ce serveur de test est isolé en mémoire, avec un port aléatoire et des identités
éphémères. Il ne modifie pas les données de démonstration et s'arrête après 10 minutes.

