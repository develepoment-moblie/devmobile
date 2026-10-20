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
- [x] Catalogue des chambres pour le Manager (création, catégorie, archive, restauration)
- [x] Signalement d’un problème à la Maintenance depuis la fiche chambre

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
| `MaintenanceRequested` reçu | chambre en maintenance (sauf si occupée) |
| `MaintenanceResolved` reçu | chambre à nettoyer après l’intervention |
| `RoomReady` émis | à la validation du nettoyage |
| `MaintenanceRequested` émis | « Signaler un problème » sur la fiche chambre |

La liste des agents vient de `session.staff` (module Utilisateurs).

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
  evidence_photo.dart           photos JPEG normalisées (1280 px, 600 Ko, sans EXIF)
```

Tables (version 4) : `housekeeping_rooms`, `housekeeping_photos`,
`housekeeping_supplies`, `housekeeping_notifications`,
`housekeeping_notification_reads`, `housekeeping_cleanings` (journal des
nettoyages : durée, score d’inspection), `housekeeping_timer_segments`,
`housekeeping_lost_items`, `housekeeping_category_tasks`,
`housekeeping_category_estimates`, `housekeeping_floors`,
`housekeeping_availability`, `housekeeping_mutations`,
`housekeeping_inspections`, `housekeeping_inspection_items`,
`housekeeping_inspection_rules`.
Une nouvelle installation reçoit des chambres et un stock fictifs.
