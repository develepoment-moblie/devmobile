# Contrat des interactions

Application française de gestion des utilisateurs, chambres et ménage sur téléphone.
Les modules métier restent indépendants ; app compose la navigation et la session.
Le thème, le logo et les widgets de shared respectent le Figma fourni.

## Canonical UI Map

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Select/Listbox | DropdownButtonFormField | Flutter Material | sélection locale | widget tests |
| Form | Form + GlobalKey + TextFormField | écrans existants | utilisateurs, chambres, attribution, stock | widget tests |
| Scrollbar | ThemeData.scrollbarTheme | app_theme.dart | listes natives | visual inspection |
| Toast | showFeedback | app_widgets.dart | succès, information | widget tests |
| CRUD | UserRepository, HotelData, RoomCatalogBackend + Navigator | SQLite et modèles | liste, détail, archives | workflow et widget tests |

## Connexion et navigation

SqliteUserRepository mémorise l’identifiant local jusqu’à Déconnexion. AuthGate route les
profils et détruit la navigation de session à la déconnexion ou au changement de
rôle. L'inscription crée un client et ouvre sa session immédiatement, sans e-mail
de confirmation. Le Manager crée les comptes du personnel sans changer sa session.
Les pastilles remplissent les identifiants fictifs sans connexion automatique.
Le bandeau « Mode local · données sur cet appareil » est permanent en mode normal.

Retour Android est coordonné par AppBackNavigation dans app/back_navigation.dart.
Il ferme d'abord le clavier, puis la page/feuille/dialogue actif via maybePop,
ensuite revient à l'onglet visité précédemment. Les onglets gardent leurs filtres,
saisies de recherche et position grâce à IndexedStack ; les doubles sélections
ne créent pas d'historique supplémentaire. Les confirmations DraftGuard et le
blocage pendant une sauvegarde restent prioritaires. SessionNavigator fournit
une pile propre à chaque identité/rôle/révision et n'est pas actif en récupération.

À la racine uniquement, le premier Retour affiche un SnackBar flottant :
« Appuyez encore sur Retour pour quitter l’application. » Un deuxième Retour
dans les deux secondes ferme l'activité Android. Expiration, interaction,
changement de page, déconnexion et passage en arrière-plan annulent cette
confirmation. Aucun écran métier n'appelle SystemNavigator.pop directement.
Les transitions Material et la mise en page existantes sont conservées.

## Mutations et formulaires

Toute mutation relit les données et le rôle dans une transaction SQLite. Les
versions périmées sont refusées. Une erreur annule toutes les écritures associées.
Les formulaires conservent les saisies après erreur ; DraftGuard protège l'abandon.
Les boutons sont désactivés pendant la sauvegarde. Les erreurs sont accessibles
et donnent une action de récupération, sans exposer les détails internes.

Le catalogue Manager conserve recherche, compteurs, états vide/chargement/erreur,
archives réversibles et confirmation d'archivage. Créer ou restaurer exige un
nouveau nettoyage. Le numéro de chambre reste stable. Manager/admin ne peut pas
contourner la validation de la gouvernante ni modifier le stock. Les agents ne
modifient que leurs tâches et doivent compléter la checklist avant soumission.
Supprimer un profil retire son accès local tout en conservant les références.

Le ménage se rafraîchit périodiquement et après les actions ; les lectures de
fond ne doivent pas écraser un brouillon. Les notifications lues sont propres à
chaque utilisateur. Les filtres et recherches sont conservés entre les onglets.
Aucune synchronisation entre appareils ni notification push n'est promise.

## Vérification

Tests : sqlite_test.dart pour persistance, rôles, conflits et transactions ;
navigation_test.dart pour Retour système, pages imbriquées, onglets, formulaires,
clavier et double Retour ; back_exit_large_text.png à 320 px / texte 200 % ;
user_merge_test.dart pour session/connexion/formulaires ; room_catalog_test.dart
pour catalogue, brouillons et accessibilité à 320 px / texte 200 % ; les tests
visuels existants conservent le Figma, Manrope et MaterialIcons.

## Sauvegardes et session persistante

SQLite mémorise l’identité jusqu’à Déconnexion, vérifie le rôle courant et refuse
les profils supprimés. Manager/admin seul exporte/restaure. Fichier externe
chiffré, mot de passe non récupérable, aucun succès après annulation du sélecteur.
La vérification affiche date et compteurs avant la confirmation de remplacement.
Une erreur conserve les données ; un succès ferme la session. Back et soumissions
répétées sont bloqués pendant l’opération. Voir backup_session_test.dart et
backup_screen_test.dart (validation, annulation, confirmation, texte 200 %).

## Espace agent

Sources métier : ../AGENTS.md, PRODUCT.md et les permissions de SqliteHousekeeping.
AuthGate active l’espace agent pour le rôle staff. MainScreen conserve la pile
Retour et trois onglets : Mon service, Mes chambres, Profil. La gouvernante garde
son espace et ses permissions. Aucun compte ni rôle n’est créé par le module ménage.
AgentWorkload sélectionne les chambres par canClean (ID en mode connecté), exclut
les chambres occupées/en maintenance et sépare soumission et validation effective.
Les compteurs décrivent les attributions actuelles, pas des statistiques datées.
La priorité de lecture est : en cours, urgent à faire, autres à faire, soumises,
validées ; le numéro de chambre stabilise l’ordre dans chaque groupe.
Les filtres ChoiceChip et le défilement persistent entre les onglets. Les tuiles
de statut ouvrent une liste filtrée avec Retour. AgentRoomCard réutilise StatusBadge
en variante lisible (11 px) et ouvre DetailsScreen pour les actions existantes.
Les boutons d’attribution et d’approbation ne sont affichés qu’à la gouvernante.
Les notifications personnelles et leur indicateur sélectionnent les chambres
encore attribuées à l’agent, plus les informations sans chambre. Aucun push ni
nouveau journal daté n’est promis. Les états vides guident vers l’actualisation
ou un autre filtre. Les erreurs conservent les données et le bandeau de reprise.
Tests : agent_dashboard_test.dart (identités, priorités, checklist, validation,
réattribution, notifications, Retour/filtres, texte 200 % et captures).

## Tâches et preuves photo

Source : demande utilisateur de photos obligatoires par tâche, tâches ajoutables
par la gouvernante et autorisation de réinitialiser les données de test.
SQLiteHousekeeping reste propriétaire des autorisations et transitions, Room et
HotelData adaptent les tâches variables. TaskSchema fournit les modèles initiaux.
Ajouter une tâche utilise Form/AlertDialog/DraftGuard, conserve le libellé après
échec et capture la version. La chambre libre redevient à nettoyer ; le nettoyage
soumis est rouvert ; occupation/maintenance restent inchangées (voir SQLITE.md).
TaskPhotoScreen demande caméra/galerie native, affiche un aperçu et exige une
confirmation avant écriture. Annulation ne coche rien. Une interruption Android
peut proposer une photo récupérée mais ne la rattache jamais automatiquement.
L’erreur conserve le brouillon ; Actualiser renouvelle la version avant une
nouvelle confirmation. Back protège les photos non enregistrées ; enregistrement
bloque doubles soumissions et Retour. Décocher avec preuve demande confirmation.
TaskPhotoViewer charge l’image à la demande et offre un nouvel essai après erreur.
Les textes de progression utilisent le nombre réel de tâches. Les démonstrations
historiques n’exposent pas les contrôles photo/personnalisation SQLite.
