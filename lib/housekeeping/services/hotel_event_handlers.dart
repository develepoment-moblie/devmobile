import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../shared/services/app_events.dart';
import 'housekeeping_store.dart';
import 'issue_rules.dart';
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
      final outOfService = room['status'] != 'occupied';
      if (outOfService) {
        room['status'] = 'maintenance';
        resetCleaning(room);
        dropOpenCleaning(state, e.roomNumber);
        room['note'] = e.description;
      }
      // Another module's report: followed up in Signalements like ours.
      issuesOf(state).insert(
        0,
        newIssue(
          roomNumber: e.roomNumber,
          category: 'autre',
          description: e.description.length > 300
              ? e.description.substring(0, 300)
              : e.description,
          priority: e.urgent ? 'urgent' : 'normal',
          outOfService: outOfService,
          reportedBy: 'system',
          reportedByName: 'Autre module',
          at: DateTime.now(),
        ),
      );
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
  // The event names only the room: every open report of the room is resolved.
  // The room stays out of service until the supervisor brings it back to
  // cleaning ("Remettre à nettoyer").
  events.on<MaintenanceResolved>().listen(
    (e) => _apply(store, (state) {
      final room = activeRoom(state, e.roomNumber);
      if (room == null) return;
      if (resolveIssues(state, e.roomNumber, DateTime.now()) == 0) return;
      final outOfService = room['status'] == 'maintenance';
      addHistory(room, 'Intervention terminée (Maintenance)');
      addNotification(
        state,
        title: 'Maintenance terminée',
        message: outOfService
            ? 'Chambre ${e.roomNumber} : intervention terminée. Remettez-la à nettoyer depuis Signalements.'
            : 'Chambre ${e.roomNumber} : intervention terminée.',
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
