# Module Chambres et ménage

Responsable : **jassernoomani** · Dossier : `lib/housekeeping/` · Tests : `test/housekeeping/`

Statut des chambres, attribution, validation, linge et produits.

## Fonctionnalités (cahier des charges)

- [x] Statut des chambres (libre, occupée, à nettoyer, maintenance)
- [x] Attribution des tâches aux agents par la gouvernante
- [x] Notification au départ du client (événement `GuestCheckedOut` des Réservations)
- [x] Validation du nettoyage par la gouvernante, avec une photo par tâche
- [x] Inspection notée : chaque point OK / partiel / non conforme (poids 1 à 5),
      score sur 100 et seuil de réussite par catégorie ; « Renvoyer en nettoyage »
      rend la chambre au même agent, en priorité, avec les points à refaire ;
      historique des inspections par chambre, score dans le journal des nettoyages
- [x] Linge et produits d’entretien (mouvements de stock)
- [x] Articles typés (linge, produits d’accueil, produits d’entretien,
      minibar) ; journal de chaque mouvement de stock par étage et chambre
      (article, quantité, personne, UUID, horodatage) ; mêmes seuils d’alerte
- [x] Blanchisserie : envoi (le linge sort du stock) puis retour, ligne par
      ligne reçu + abîmé + perdu = envoyé ; seul le reçu revient en stock
- [x] Demandes de fournitures des agents : demandée → approuvée → préparée →
      livrée, ou refusée ; le stock baisse à la livraison (refusée s’il manque
      du stock) ; l’agent est prévenu à chaque étape
- [x] Notifications par catégorie (tâches urgentes et reprises, départs,
      nettoyages à valider, stock, maintenance, retards, autres), chacun
      choisit les siennes ; « Tâche urgente » pour l’agent attribué ;
      « Nettoyage en retard » pour la gouvernante quand le minuteur dépasse le
      temps prévu de la catégorie + 25 % (une fois par nettoyage)
- [x] Tableau de bord (gouvernante, Manager) : chambres par statut, nettoyés
      et à faire, temps moyen (minuteur), chambres par heure et score moyen
      par agent, signalements ouverts ; mis à jour en direct
- [x] Minibar : carte avec prix (gouvernante ou Manager), consommations par
      chambre (en attente → facturé), réassort ; « Valider et facturer » envoie
      `ExtraCharged` une seule fois par consommation ; après facturation, une
      correction passe par une écriture compensatoire
- [x] Catalogue des chambres pour le Manager (création, catégorie, archive, restauration)
- [x] Signalement d’un problème à la Maintenance depuis la fiche chambre :
      catégorie (Climatisation, Éclairage, Plomberie, Télévision, Mobilier,
      Autre), description, priorité (basse à urgente), jusqu’à 3 photos, note
      vocale facultative (1 minute maximum) et option « Mettre la chambre hors
      service » ; écran « Signalements » (Signalé → Résolu → Clôturé)
- [x] Objets trouvés : Trouvé → Client prévenu → Remis, ou Archivé (à la main ou
      automatiquement après un délai réglable, 30 jours par défaut) ; chaque
      tentative de contact est notée (date, moyen, message) ; recherche, filtres
      par statut, chambre et date ; historique complet de chaque objet

## Qui voit quoi

| Rôle | Écran |
|---|---|
| Agent d’étage | Mon service, Mes chambres : uniquement ses attributions |
| Gouvernante | Accueil, Départs, Chambres, Stock, Ménage (validation) |
| Manager / Admin | Catalogue des chambres |

Seule la gouvernante attribue, valide et gère le stock. Un agent ne modifie que
les chambres qui lui sont attribuées. Le Manager ne nettoie pas et ne touche pas
au stock. Ces règles sont locales (`services/sqlite_housekeeping.dart`).

## Avec les autres modules

| Événement | Effet ici |
|---|---|
| `GuestCheckedIn` reçu | chambre occupée |
| `GuestCheckedOut` reçu | chambre à nettoyer + notification « Départ client » |
| `MaintenanceRequested` reçu | chambre en maintenance (sauf si occupée) + signalement « Autre module » |
| `MaintenanceResolved` reçu | signalements de la chambre résolus + notification ; la chambre reste hors service jusqu’à « Remettre à nettoyer » (gouvernante) |
| `RoomReady` émis | à la validation du nettoyage |
| `ExtraCharged` émis | « Valider et facturer » du minibar (une fois par consommation, montant négatif pour une correction) |
| `GuestCheckedIn` / `GuestCheckedOut` reçus | séjour noté (chambre, nom) : une consommation n’est facturée que si son client est toujours là |
| `MaintenanceRequested` émis | « Signaler un problème » sur la fiche chambre |

La liste des agents vient de `session.staff` (module Utilisateurs).

Mise à jour en direct, sans minuterie : le magasin (`HousekeepingStore`)
signale chaque enregistrement réussi (action d’un écran ou événement d’un
autre module) ; `HotelData` et `DashboardData` relisent alors les données.
Notifications du téléphone : affichées tant que l’application tourne (ouverte
ou en arrière-plan), pas de serveur ni de notification à distance.

Limites des événements partagés (à voir avec le module Maintenance) :
`MaintenanceRequested` ne porte que la chambre, une description et « urgent ».
La catégorie est ajoutée en tête de la description (`[Plomberie] …`), « urgent »
vaut priorité haute ou urgente ; les photos, la note vocale et l’identifiant du
signalement restent ici (`housekeeping_issues`). `MaintenanceResolved` ne porte
que la chambre : il résout donc tous les signalements ouverts de la chambre.
Les coordonnées des clients ne sont pas transmises au ménage (`GuestCheckedIn`
ne donne que le nom) : « Prévenir le client » note la tentative sans appeler.

Limites pour la facturation : `ExtraCharged` ne porte que la chambre, un
libellé et un montant. Pas d’identifiant de charge (la facturation ne peut pas
dédoublonner de son côté), pas de lien vers un séjour ou une réservation
(`GuestCheckedIn` ne donne que le nom, `GuestCheckedOut` rien), pas
d’accusé de réception. À demander : `chargeId`, `stayId`/`reservationId`,
montants négatifs acceptés pour les corrections.

Note vocale : fichier `housekeeping/voice/<uuid>.m4a` dans le dossier de
l’application (paquets `record`, `audioplayers`, `path_provider`, permission
`RECORD_AUDIO`) ; SQLite ne garde que ce chemin relatif. Une note enregistrée
puis abandonnée est supprimée du téléphone.

## Structure

```text
housekeeping_module.dart        point d’entrée : tables, écoute des événements, 1er écran
models/                         Room, Supply, HotelData (état des écrans), AgentWorkload, TaskSchema
custom/                         cartes, dialogues (stock, tâche, signalement), en-tête, icônes
screens/
  housekeeping_home_screen.dart choix de l’écran selon le rôle
  housekeeping_workspace.dart   onglets de l’agent et de la gouvernante
  …                             chambres, fiche, attribution, photo, stock, notifications, catalogue
services/
  housekeeping_store.dart       tables SQLite housekeeping_* et transactions
  sqlite_housekeeping.dart      règles du ménage (attribution, contrôle, validation, stock)
  sqlite_room_catalog.dart      règles du catalogue Manager
  hotel_event_handlers.dart     réactions aux événements des autres modules
  room_rules.dart               petites opérations communes sur une chambre
  inspection_scoring.dart       notes, poids, score et seuil d’inspection (pur Dart)
  issue_rules.dart              signalements, archivage des objets trouvés
  inventory_rules.dart          journal du stock, blanchisserie, demandes, minibar
  notification_rules.dart       catégories de notifications, retards
  dashboard_queries.dart        requêtes SQL du tableau de bord
  voice_notes.dart              enregistrement et lecture des notes vocales
  evidence_photo.dart           photos JPEG normalisées (1280 px, 600 Ko, sans EXIF)
```

Tables (version 7) : `housekeeping_rooms`, `housekeeping_photos`,
`housekeeping_supplies`, `housekeeping_notifications`,
`housekeeping_notification_reads`, `housekeeping_cleanings` (journal des
nettoyages : durée, score d’inspection), `housekeeping_timer_segments`,
`housekeeping_lost_items`, `housekeeping_category_tasks`,
`housekeeping_category_estimates`, `housekeeping_floors`,
`housekeeping_availability`, `housekeeping_mutations`,
`housekeeping_inspections`, `housekeeping_inspection_items`,
`housekeeping_inspection_rules`, `housekeeping_issues`,
`housekeeping_issue_photos`, `housekeeping_lost_item_events` (historique des
objets trouvés), `housekeeping_settings` (délai d’archivage),
`housekeeping_stock_movements` (journal du stock),
`housekeeping_laundry_batches`, `housekeeping_laundry_lines`,
`housekeeping_supply_requests`, `housekeeping_supply_request_lines`,
`housekeeping_minibar_consumptions`, `housekeeping_stays`,
`housekeeping_notification_prefs`.
Une nouvelle installation reçoit des chambres et un stock fictifs.
