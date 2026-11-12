# Module Réservations

Responsable : **Yassmine** · Dossier : `lib/reservations/` · Tests : `test/reservations/`

Réservations, disponibilités, tarifs, check-in et check-out.

## Fonctionnalités (cahier des charges)

- [x] Création et annulation (modification : à faire)
- [ ] Calendrier de disponibilité
- [ ] Tarifs, saisons et promotions
- [x] Check-in et check-out
- [ ] Fiche client et historique

## Structure

- `reservations_module.dart` : point d’entrée (titre, rôles, tables, premier écran).
- `models/` : classes de données.
- `custom/` : widgets réutilisables du module.
- `screens/` : écrans. `reservations_home_screen.dart` est le premier écran.
- `services/` : accès à la base SQLite et logique métier.

Tables SQLite : préfixe obligatoire `reservations_` (voir CONTRIBUTING.md).

## Écrans

- **Réserver** (`search_screen.dart`) : dates, nombre de personnes, chambres
  libres, et recherche d'hôtels à Paris avec StayingAPI.
- **Détail chambre** puis **Confirmation** : création de la réservation.
- **Séjours** (`my_stays_screen.dart`) : réservations, check-in, check-out,
  annulation.

Les réservations sont gardées en mémoire (`ReservationService`) : elles
disparaissent quand l'application redémarre. Pour les garder, il faudra une
table `reservations_bookings` dans la base commune.

## Clé StayingAPI

La clé n'est pas écrite dans le code. On la donne au lancement :

```
flutter run --dart-define=STAYING_API_KEY=stay_test_...
```

Sans clé, le bouton de recherche StayingAPI affiche « Clé StayingAPI absente ».
Le reste du module marche sans clé.
