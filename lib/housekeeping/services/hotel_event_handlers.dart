import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../shared/services/app_events.dart';
import 'housekeeping_store.dart';
import 'room_rules.dart';

// How housekeeping reacts to the other modules (see lib/shared/services/app_events.dart).
// Unknown or archived rooms are ignored: the other module may know rooms
// housekeeping does not manage.
List<StreamSubscription<AppEvent>> listenToHotelEvents(
  AppEvents events,
  HousekeepingStore store,
) => [
  events.on<GuestCheckedIn>().listen(
    (e) => _apply(store, (state) {
      final room = activeRoom(state, e.roomNumber);
      if (room == null || room['status'] == 'occupied') return;
      room['status'] = 'occupied';
      room['priority'] = 'normal';
      resetCleaning(room);
      room['stayover'] = false;
      dropOpenCleaning(state, e.roomNumber);
      room['note'] = '';
      addHistory(room, 'Client installé : ${e.guestName} (Réservations)');
      bumpVersion(room);
    }),
  ),
  events.on<GuestCheckedOut>().listen(
    (e) => _apply(store, (state) {
      final room = activeRoom(state, e.roomNumber);
      if (room == null) return;
      if (room['status'] == 'maintenance') {
        addHistory(room, 'Départ du client · maintenance en cours');
      } else {
        room['status'] = 'dirty';
        resetCleaning(room);
        room['stayover'] = false;
        // A departure is cleaned before ordinary rooms.
        if (room['priority'] == null || room['priority'] == 'normal') {
          room['priority'] = 'checkout';
        }
        dropOpenCleaning(state, e.roomNumber);
        room['note'] = 'Le client vient de quitter la chambre';
        addHistory(room, 'Départ du client · chambre à nettoyer');
        addNotification(
          state,
          title: 'Départ client',
          message:
              'Le client a quitté la chambre ${e.roomNumber}. Un nettoyage est à prévoir.',
          roomNumber: e.roomNumber,
        );
      }
      bumpVersion(room);
    }),
  ),
  events.on<MaintenanceRequested>().listen((e) {
    if (store.takeOwnReport(e.roomNumber)) return;
    _apply(store, (state) {
      final room = activeRoom(state, e.roomNumber);
      if (room == null || room['status'] == 'maintenance') return;
      if (room['status'] != 'occupied') {
        room['status'] = 'maintenance';
        resetCleaning(room);
        dropOpenCleaning(state, e.roomNumber);
        room['note'] = e.description;
      }
      addHistory(room, 'Problème signalé : ${e.description}');
      addNotification(
        state,
        title: e.urgent ? 'Maintenance urgente' : 'Maintenance',
        message: 'Chambre ${e.roomNumber} : ${e.description}',
        roomNumber: e.roomNumber,
        audience: 'supervisor',
      );
      bumpVersion(room);
    });
  }),
  events.on<MaintenanceResolved>().listen(
    (e) => _apply(store, (state) {
      final room = activeRoom(state, e.roomNumber);
      if (room == null || room['status'] != 'maintenance') return;
      room['status'] = 'dirty';
      resetCleaning(room);
      room['note'] = 'Nettoyage après intervention';
      addHistory(room, 'Intervention terminée · chambre à nettoyer');
      addNotification(
        state,
        title: 'Maintenance terminée',
        message: 'Chambre ${e.roomNumber} à nettoyer après l’intervention.',
        roomNumber: e.roomNumber,
        audience: 'supervisor',
      );
      bumpVersion(room);
    }),
  ),
];

// Events have no screen to show an error on: keep the app running and log it.
void _apply(
  HousekeepingStore store,
  void Function(Map<String, dynamic>) change,
) => store
    .systemChange(change)
    .catchError(
      (Object error) => debugPrint('housekeeping: événement ignoré ($error)'),
    );
