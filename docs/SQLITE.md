# Nova Paris — SQLite local

Le lancement normal utilise sqflite et `nova_paris.db` dans le dossier privé des
bases de données de l'application. Dans Android Studio, choisir le téléphone
et lancer lib/main.dart. Aucun serveur ou accès Internet n'est nécessaire après
installation. Arrêter complètement puis Run : le hot reload ne relance pas main().
Retirer les anciens arguments de backend de la configuration Run.

Sur le téléphone de test, utiliser **Nova Paris - Phone (release)** dans Android
Studio pour les essais depuis l'icône, sans débogueur. La version release conserve
la même base SQLite. Le passage debug → release ne nécessite ni désinstallation
ni effacement des données. Conserver main.dart en mode debug pour coder avec hot reload.

```powershell
C:\flutter\bin\flutter.bat pub get
C:\flutter\bin\flutter.bat run -d uwvc4p59vgqceajr
```

## Première ouverture

Une nouvelle base reçoit les chambres, fournitures et comptes fictifs du cours.
Aucune donnée extérieure ou de l'ancienne démo JSON n'est importée. Les données
persistent après fermeture et mise à jour de l'application. La connexion est
conservée jusqu’à la déconnexion. Seul l’identifiant du profil est mémorisé dans
metadata ; le rôle et la suppression sont revérifiés en base.

Mot de passe initial commun : `Nova123!`.

| E-mail | Rôle |
|---|---|
| manager@nova.test | Manager : utilisateurs et catalogue des chambres |
| amina@nova.test | Gouvernante : attribution, validation et stock |
| sarah@nova.test | Agent |
| lina@nova.test | Agent |
| youssef@nova.test | Agent |
| guest@nova.test | Client |

Les pastilles remplissent les identifiants sans connecter automatiquement.
Le Manager peut créer des comptes utilisables sur cet appareil. L'inscription
publique crée un client et le connecte immédiatement, sans confirmation e-mail.
Chaque utilisateur change son mot de passe depuis son Profil. En cas d’oubli,
le Manager le réinitialise depuis Utilisateurs avec un mot de passe temporaire.
Le Manager gère aussi la liste des Priorités affichée sur son accueil.

Pour tester : Amina attribue la chambre 305 à Sarah ; Sarah démarre, coche les
tous les contrôles avec leurs photos et termine ; Amina valide. Le Manager peut créer, modifier,
archiver et restaurer des chambres. Créer ou restaurer exige un nettoyage.

Sarah et les autres agents ouvrent Mon service avec leurs propres attributions.
La chambre en cours est proposée avant les tâches urgentes, puis les autres
chambres. Mes chambres propose Toutes / À faire / En cours / À valider / Validées.
Une chambre soumise reste À valider jusqu’au contrôle d’Amina ; seule cette
validation la rend disponible. Les compteurs ne sont pas des statistiques par jour.

## Structure et intégrité

### Sauvegarde et restauration

Manager/admin → Données locales → Sauvegarder et restaurer. Choisir un mot de
passe de 8 caractères minimum puis exporter le fichier `.nova-backup` avec le
sélecteur Android. Conserver le fichier hors du stockage privé de l’application
et garder son mot de passe : aucun mécanisme de récupération n’existe.

Le fichier contient utilisateurs (hashes), chambres actives et archivées, tâches,
historiques, photos justificatives, stock et notifications lues. Il ne contient pas la session.
Chiffrement AES-256-GCM avec sel et nonce aléatoires, clé PBKDF2-SHA256 à
210 000 itérations ; calcul dans un isolate. Limite 64 Mo, photos comprises.
Format 2 ; les fichiers de format 1 restent importables. Les anciens contrôles des
chambres à nettoyer sont alors réinitialisés car ils n’ont pas de photos.

Pour restaurer : choisir le fichier, saisir son mot de passe, vérifier la date et
les compteurs, puis confirmer le remplacement. Toutes les données de cet appareil
sont remplacées dans une transaction unique. Une erreur conserve les données
actuelles. Après succès, se reconnecter avec un compte de la sauvegarde. Exporter
les données actuelles avant remplacement si elles doivent être conservées.
Aucune fusion ni synchronisation automatique entre appareils.

- lib/shared/services/local_database.dart : schéma version 2, ouverture et SQL.
- lib/shared/services/local_session_store.dart : contrat partagé des adaptateurs.
- lib/shared/services/local_seed.dart : exemples à la première ouverture seulement.
- lib/user_management/services/user_repository.dart : contrat utilisateur et erreurs.
- lib/user_management/services/sqlite_user_repository.dart : profils, connexion,
  session locale et transactions.
- lib/housekeeping/services/sqlite_housekeeping.dart : ménage et stock.
- lib/housekeeping/services/sqlite_room_catalog.dart : catalogue et archives.
- lib/app/auth_gate.dart : composition et navigation des sessions.

Tables : users, rooms, supplies, notifications, notification_reads, metadata, task_photos.
Tâches, checklist et historique sont des listes JSON dans les colonnes de rooms ; les
autres propriétés sont des colonnes SQL. Le drapeau archived conserve le numéro
unique des chambres archivées. Les clés étrangères sont activées. Les profils
supprimés sont conservés avec deleted=1 pour l'historique, et ne peuvent plus
se connecter.

Chaque mutation lit l'état courant, vérifie rôle et version, puis écrit dans une
transaction unique. Une erreur annule toute la mutation. Les écrans ne reçoivent
jamais les hashes. Chaque compte possède son sel aléatoire et un hash
PBKDF2-SHA256 à 100 000 itérations ; aucun mot de passe en clair n'est sauvegardé.
Une évolution du schéma doit augmenter version et fournir un onUpgrade préservant
les données. Ne pas supprimer la base à chaque lancement ni écraser une base illisible.

sqlite_test.dart utilise un vrai fichier temporaire avec sqflite_common_ffi :
relancements, permissions, notifications, archives, conflits et rollback SQL.

## Tâches personnalisées et photos

Gouvernante → Chambres → ouvrir une chambre → Ajouter une tâche à cette chambre.
Chaque chambre conserve ses tâches (quatre modèles initiaux, puis jusqu’à 40).
Une tâche ajoutée à un nettoyage soumis rouvre le travail. Une chambre libre
redevient à nettoyer, avec remise à zéro de ses contrôles/photos. Une chambre
occupée ou en maintenance conserve son statut ; la tâche est prévue pour son
prochain nettoyage. Les définitions survivent à l’archivage/restauration.

Agent → reprendre une chambre → cocher une tâche → prendre une photo ou choisir
dans la galerie → vérifier → Enregistrer la photo et terminer la tâche.
Sans confirmation, aucune tâche n’est cochée. Toutes les tâches doivent être
terminées et justifiées avant soumission, puis contrôlées par la gouvernante.
Voir la photo ouvre l’image pour l’agent attribué ou la gouvernante.

Photos JPEG normalisées (1280 px et 600 Ko maximum), stockées dans SQLite avec
références stables par tâche ; aucun chemin de galerie n’est conservé. Les EXIF
sont retirés. Source : 10 Mo maximum. Les instantanés périodiques ne contiennent
pas les images, chargées à la demande. Photo et contrôle sont écrits dans la même
transaction. Décocher ou réattribuer retire l’ancienne preuve. Les photos sans
référence sont supprimées. Une photo récupérée après interruption Android est
proposée à nouveau, jamais appliquée automatiquement à une tâche.

La migration 1 → 2 conserve chambres/comptes mais remet les contrôles des chambres
sales à zéro, comme autorisé pour les données de test. Les démonstrations
JSON/Node/mémoire gardent leur checklist historique sans photos.

## Limites locales

Chaque téléphone possède ses propres utilisateurs et données. Aucune
synchronisation ou notification push. Le bandeau « Mode local · données sur cet
appareil » le rappelle. Les permissions sont des contrôles applicatifs locaux,
sans garantie serveur. La base n'est pas chiffrée ; les exemples sont destinés
au cours et leurs identifiants sont publics.

Pour repartir de zéro : Android → Paramètres → Applications → Nova Paris →
Stockage → Effacer les données. Cela supprime définitivement les données locales ;
la prochaine ouverture recrée les exemples. Une mise à jour normale ne l'exige pas.

Le lancement SQLite cible Android/iOS/macOS. Les tests Windows utilisent FFI.
Pour le Web, seule la démo JSON historique est disponible.

## Anciennes démonstrations séparées

- LOCAL_JSON_DEMO=true : ancienne démo shared_preferences.
- HOUSEKEEPING_DEMO=true : ancienne démo ménage en mémoire.
- HOUSEKEEPING_API_URL / HOUSEKEEPING_TOKEN : ancienne API Node/SQLite.

Utiliser --dart-define pour ces arguments uniquement si la démonstration est voulue.
Voir OFFLINE.md et ../backend/README.md. Leurs données restent indépendantes.
