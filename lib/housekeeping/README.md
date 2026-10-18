# Module chambres et ménage

Ce dossier possède le travail de gestion des chambres et du ménage, comme
`user_management/` possède le module utilisateur.

```text
housekeeping/
  housekeeping.dart           API publique du module
  models/
    hotel_data.dart           État et actions du ménage
    room.dart
    supply.dart
  custom/
    roomcard.dart
    stock_movement_dialog.dart
  screens/
    housekeeping_screen.dart
    rooms_screen.dart
    details_screen.dart
    assign_task_screen.dart
    supplies_screen.dart
    notifications_screen.dart
    staff_screen.dart
    manage_rooms_screen.dart  Catalogue du Manager et formulaire de chambre
  services/
    housekeeping_backend.dart Contrat de stockage
    sqlite_housekeeping.dart   Adaptateur local SQLite
    housekeeping_api.dart     Ancien adaptateur HTTP de démonstration
    room_catalog_backend.dart Contrat du catalogue Manager
    sqlite_room_catalog.dart  Création, modification et archivage SQLite
```

Les écrans reçoivent `HotelData` depuis l'application. Ce module n'importe ni
`user_management`, ni `app`, ni `demo`. Les widgets communs, le thème et les erreurs
de service viennent de `shared/`. Aucun second MaterialApp ni connexion séparée.

Pour intégrer un écran depuis un autre module ou le routeur :

```dart
import 'package:nova_paris/housekeeping/housekeeping.dart';

// Après chargement de HotelData avec la session partagée :
HousekeepingScreen(data: hotelData);
```

`lib/housekeeping.dart` reste une entrée de compatibilité. Les adaptateurs SQLite
utilisent le contrat partagé LocalSessionStore ; les écrans gardent les mêmes
interfaces et les règles métier. Voir SQLITE.md à la racine.
