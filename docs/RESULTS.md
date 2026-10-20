# Vérification — application locale

Le lancement normal utilise sqflite et nova_paris.db. Les adaptateurs utilisateur,
ménage et catalogue partagent des transactions SQLite et conservent les frontières
des modules. Les anciennes démonstrations restent isolées.

Les tests sqlite_test.dart couvrent :
- création et suppression logique des comptes, connexion et persistance ;
- rôles, versions périmées et session du Manager ;
- attribution, checklist, soumission, validation et stock ;
- notifications lues propres à chaque utilisateur ;
- catalogue, archives, restauration et unicité des numéros ;
- conflits entre connexions et annulation complète des écritures SQL en échec.

Les tests de widgets existants couvrent la navigation de session, les brouillons,
les formulaires et les rendus Figma avec Manrope et MaterialIcons.

L'installation et le parcours interactif de cette version sur téléphone restent
à effectuer depuis Android Studio. Voir SQLITE.md pour le lancement et les comptes.

## Validation du 16 octobre 2026 — nettoyage des anciennes intégrations

- flutter analyze : aucune anomalie.
- flutter test : 55 réussis, 1 test historique de l'API Node réelle ignoré.
- Nouvelle inscription locale testée jusqu'à l'ouverture de la session client.
- Dépendances et registres de plugins régénérés après flutter clean et pub get.
- Compilation Android arm64 debug réussie : build/app/outputs/flutter-apk/app-debug.apk.
- Recherche des anciennes références dans les sources, tests, documentation,
  configuration IDE et dépendances : aucun résultat.
- Aucun changement aux données SQLite existantes de l'appareil ni à un service distant.

## Navigation Android — 16 octobre 2026

- AppBackNavigation délègue Retour à SessionNavigator avec maybePop avant de
  parcourir l'historique des onglets. Les confirmations DraftGuard restent actives.
- À la racine, premier Retour : instruction dans le SnackBar vert ; deuxième
  Retour sous deux secondes : SystemNavigator.pop sur Android uniquement.
- Navigation, interaction, déconnexion et arrière-plan annulent la confirmation.
- IndexedStack conserve filtres/recherches/position ; re-sélection sans doublon.
- Le raccourci des nettoyages à valider ouvre maintenant Ménage au lieu de Stock.
- flutter analyze : aucune anomalie.
- Suite complète : 70 tests réussis, 1 ancien test d'API réelle ignoré.
- Dernière vérification ciblée : 15 tests de navigation réussis.
- Couverture : pages imbriquées, notifications/détails, onglets, feuilles, brouillons,
  sauvegarde en cours, clavier, expiration, déconnexion et reprise de l'application.
- Rendu inspecté : ../test/goldens/back_exit_large_text.png, 320 x 568, texte 200 %,
  Manrope et MaterialIcons ; autres baselines Figma conservées.
- APK Android arm64 debug compilé avec succès.
- Le test matériel du geste/bouton Retour reste à effectuer sur le téléphone après
  arrêt complet et Run dans Android Studio ; aucune installation n'a été effectuée ici.

## Écran noir après réouverture — 16 octobre 2026

- Reproduction confirmée par l'utilisateur sur l'APK debug installé depuis Android Studio.
- Capture du noir : ../verification/black-screen-debug.png. Aucun crash Dart enregistré.
- Le processus debug portait pause_isolates_on_start=true ; les états observés
  n'établissent pas à eux seuls la cause interne exacte du blocage.
- Flutter 3.47.7, téléphone Xiaomi 21081111RG / MT6893, Android 14 ; Impeller GLES.
- Comparaison sans changement de code ni de backend graphique : APK release arm64
  compilé et installé avec adb install -r. Les données SQLite ont été conservées.
- Démarrage à froid réussi ; recréation de l'activité dans le même processus réussie
(warm launch 224 ms). Captures ../verification/reopen-release-before.png et ../verification/reopen-release-warm.png.
- L'utilisateur a ensuite confirmé que double Retour → icône ouvre normalement
  la connexion sans forcer l'arrêt du processus.
- Configuration Android Studio ajoutée : Nova Paris - Phone (release), --release.
  La configuration de développement main.dart reste séparée, avec hot reload.
- Aucun contournement de moteur graphique, suppression de base ou changement de
  navigation n'a été nécessaire. Le build release installé fonctionne sans IDE.

## 2026-10-16 — Sessions et sauvegardes SQLite

- Identité conservée dans metadata ; déconnexion persistante, rôles actuels et
  profils supprimés contrôlés après réouverture. Aucun mot de passe mémorisé.
- Manager/admin : export chiffré AES-256-GCM / PBKDF2-SHA256, sélecteur natif,
  import limité à 10 Mo, validation et aperçu avant remplacement confirmé.
- Restauration atomique : sessions exclues, fermeture après succès, rollback
  testé par échec SQL forcé. Aucun remplacement de la base du téléphone en test.
- flutter analyze : aucune anomalie. flutter test : 83 réussis, 1 test historique
  dépendant du serveur ignoré. 9 tests session/sauvegarde, 4 tests écran ajoutés.
- Capture ../test/goldens/backup_large_text.png inspectée à 320 × 568, texte 200 % ;
  formulaire défilant sans débordement. Annulation, double soumission, Retour
  pendant opération et confirmation de remplacement vérifiés.
- Le sélecteur Android reste à tester manuellement sur le téléphone (export puis
  sélection/vérification du fichier). Les tests de remplacement utilisent une
  base temporaire ; ils n’effacent aucune donnée réelle.
- APK release arm64 construit (19,1 Mo), installé avec adb install -r : Success.
  Base existante conservée, aucune désinstallation ni effacement.

## 2026-10-16 — Espace personnel agent

- Mon service démarre pour staff : compteurs personnels, chambre à reprendre,
  priorités et progression de checklist. Mes chambres conserve ses filtres.
- Sélection par ID avec les transports authentifiés, pas par nom. Une attribution
  retirée disparaît du planning personnel. Les compteurs sont les attributions
  actuelles ; aucune statistique quotidienne ni horaire inventé.
- Les détails réutilisent les actions existantes. Attribution et validation sont
  affichées à la gouvernante seulement. Pas de changement des permissions SQLite.
- Notifications personnelles filtrées sur les chambres encore attribuées ; les
  lectures restent propres au compte. Pas de nouvelle notification push.
- flutter analyze : aucune anomalie. flutter test : 91 réussis, 1 ancien test
  dépendant du serveur ignoré ; journal agent-dashboard-tests.log.
- 8 nouveaux tests : isolation par ID malgré noms identiques, priorité, checklist
  et approbation, réattribution, notifications, filtres/Retour, texte 200 % et
  captures agent_dashboard.png / agent_rooms.png inspectées visuellement.
- Baselines Figma housekeeping/assignment conservées. Audit premium strict :
  zéro anomalie (premium-audit.json). Build release arm64 : succès, 19,2 Mo.
- Les comptes/profils restent dans user_management. Nouveaux écrans et modèle dans
  housekeeping, navigation composée dans app. Aucune migration ni remise à zéro.
- APK installé sur le téléphone avec adb install -r : Success ; données conservées. La vérification des interactions sur téléphone reste manuelle.

## 2026-10-16 — Tâches variables et photo obligatoire

- SQLite v2 : tâches par chambre dans rooms.tasks, JPEG normalisés dans task_photos.
  Les instantanés excluent les octets des photos ; lecture à la demande et accès
  réservé à la gouvernante ou à l’agent attribué. Modèles initiaux : TaskSchema.
- Contrôle et photo atomiques ; aucune validation sans photo. Les erreurs SQL
  annulent les deux. Décocher/réattribuer retire les preuves devenues inutiles.
- Gouvernante : ajout de tâches par chambre, refus des doublons et versions
  périmées, conservation du brouillon après erreur, 40 tâches maximum. Ajout après
  soumission rouvre le nettoyage ; chambre prête redevient sale ; occupation et
  maintenance conservées. Définitions conservées dans les archives.
- Agent : caméra/galerie, aperçu, confirmation ; annulation sans mutation, Back
  protégé, doubles soumissions bloquées, brouillon conservé sur conflit et version
  renouvelée par Actualiser. Récupération Android jamais appliquée automatiquement.
- Photos bornées à 1280 px / 600 Ko, EXIF retirés. Sauvegardes format 2, photos
  incluses, limite 64 MiB ; import format 1 et réinitialisation des anciens
  contrôles sales sans preuve. Migration 1→2 testée (données de test réinitialisables
  explicitement autorisées par l’utilisateur).
- flutter analyze : aucune anomalie. Suite complète : 108 réussis, 1 test ancien
  dépendant d’un serveur ignoré. Journal task-photos-tests.log.
- 17 tests ajoutés : 8 persistance/domaine/migration/backup/image ; 9 écran,
  récupération caméra, annulation, conflit, brouillon, busy/Retour et texte 200 %.
- Capture task_photo.png inspectée visuellement, aperçu JPEG effectivement chargé.
  Les autres captures Figma restent valides. Audit premium strict sans anomalie.
- Build release arm64 réussi (20,3 Mo). Caméra/galerie natives : validation manuelle
  sur téléphone encore nécessaire ; les tests écran utilisent un picker injecté.
- Installation finale adb install -r : Success ; lancement natif vérifié. Test ciblé supplémentaire de compatibilité des sauvegardes avec photos : réussi.

## 2026-10-20 — Mots de passe et accueil client

- Profil : « Changer le mot de passe » (mot de passe actuel requis, 6 caractères
  minimum, confirmation). Disponible pour tous les rôles, client compris.
- Manager/admin : Utilisateurs → « Réinitialiser le mot de passe » avec un mot de
  passe temporaire. Version vérifiée ; son propre compte passe par le Profil.
- Connexion : « Mot de passe oublié ? » explique la réinitialisation par le Manager
  (aucun service d’e-mail local). Contrat optionnel PasswordManagement ; les
  démonstrations héritées restent inchangées.
- Accueil client : bouton Profil à la place de la cloche inactive, « Tout voir »
  inactif masqué, recherche de dates orientée vers la réception.
- flutter analyze : aucune anomalie. flutter test : 109 réussis, 1 ancien test
  dépendant du serveur ignoré. Mots de passe jamais stockés en clair (test ajouté).
- Nettoyage : anciens journaux de crash JVM/Kotlin supprimés. Archive de rendu
  ../nova_paris-submission.zip générée selon .gitignore (sans build, .dart_tool,
  backend/.dev, données SQLite ni chemins locaux).

## 2026-10-20 — Fusion de la branche Gestion-user (Skander256)

Source : github.com/develepoment-moblie/devmobile, branche Gestion-user, commit 8101a00.

Repris et adapté :
- Priorités du Manager (liste, ajout, modification, suppression ; icône et type).
  Table SQLite priorities (schéma v3), version vérifiée, actions réservées au
  Manager/admin, incluses dans les sauvegardes (optionnelles pour les anciennes).
  Trois exemples fictifs ajoutés à la création et à la migration 2 → 3.
- Accueil Manager : section Priorités (trois premières) et bouton de gestion.

Non repris :
- DatabaseHelper : mots de passe et réponses secrètes en clair, suppression
  définitive, aucune vérification de rôle, même fichier nova_paris.db avec un
  schéma incompatible.
- Réinitialisation Firebase : nécessite Internet, n’agit que sur des comptes
  Firebase (inexistants ici) et contient une clé API publiée. Remplacée par la
  réinitialisation locale du Manager.
- Connexion Google : configuration OAuth absente, mot de passe en clair prévisible
  pour les comptes créés. flutter_facebook_auth : dépendance inutilisée.
- Statistiques (82 %, 24,8 k€), profil (Visa, réservations) et accueil agent :
  valeurs fictives fixes ; facturation et réservations relèvent d’autres modules,
  et l’espace agent réel existe déjà.
- Changement rapide de rôle : déjà couvert par Modifier, avec confirmation.

- flutter analyze : aucune anomalie. flutter test : 110 réussis, 1 ancien test
  dépendant du serveur ignoré. Test ajouté : priorités, permissions, conflit de
  version, persistance et sauvegarde ; test de migration étendu à v3.
