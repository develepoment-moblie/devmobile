import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../shared/services/app_events.dart';
import 'housekeeping_store.dart';
import 'mutation_meta.dart';
import 'inventory_rules.dart';
import 'issue_rules.dart';
import 'room_rules.dart';

// How housekeeping reacts to the other modules (see lib/shared/services/app_events.dart).
// Unknown or archived rooms are ignored: the other module may know rooms
// housekeeping does not manage.
List<StreamSubscription<AppEvent>> listenToHotelEvents(
  AppEvents events,
  HousekeepingStore store,
) => [
  events.on<GuestCheckedIn>().listen((e) => _apply(store, e)),
  events.on<GuestCheckedOut>().listen((e) => _apply(store, e)),
  events.on<MaintenanceRequested>().listen((e) {
    // A report made here was already applied by the rules.
    if (store.takeOwnReport(e.roomNumber)) return;
    _apply(store, e);
  }),
  events.on<MaintenanceResolved>().listen((e) => _apply(store, e)),
];

/// What [event] changes in the housekeeping [state]. Times come from
/// [mutationNow] (the change's time, see HousekeepingStore.systemChange).
void applyHotelEvent(Map<String, dynamic> state, AppEvent event) {
  final room = activeRoom(state, event.roomNumber);
  if (room == null) return;
  switch (event) {
    case GuestCheckedIn(:final guestName):
      if (room['status'] == 'occupied') return;
      // Who is in the room: minibar charges belong to this stay.
      checkIn(state, event.roomNumber, guestName, mutationNow());
      room['status'] = 'occupied';
      room['priority'] = 'normal';
      resetCleaning(room);
      room['stayover'] = false;
      dropOpenCleaning(state, event.roomNumber);
      room['note'] = '';
      addHistory(room, 'Client installé : $guestName (Réservations)');
    case GuestCheckedOut():
      checkOut(state, event.roomNumber, mutationNow());
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
        dropOpenCleaning(state, event.roomNumber);
        room['note'] = 'Le client vient de quitter la chambre';
        addHistory(room, 'Départ du client · chambre à nettoyer');
        addNotification(
          state,
          title: 'Départ client',
          message:
              'Le client a quitté la chambre ${event.roomNumber}. Un nettoyage est à prévoir.',
          roomNumber: event.roomNumber,
        );
      }
    case MaintenanceRequested(:final description, :final urgent):
      if (room['status'] == 'maintenance') return;
      final outOfService = room['status'] != 'occupied';
      if (outOfService) {
        room['status'] = 'maintenance';
        resetCleaning(room);
        dropOpenCleaning(state, event.roomNumber);
        room['note'] = description;
      }
      // Another module's report: followed up in Signalements like ours.
      issuesOf(state).insert(
        0,
        newIssue(
          roomNumber: event.roomNumber,
          category: 'autre',
          description: description.length > 300
              ? description.substring(0, 300)
              : description,
          priority: urgent ? 'urgent' : 'normal',
          outOfService: outOfService,
          reportedBy: 'system',
          reportedByName: 'Autre module',
          at: mutationNow(),
        ),
      );
      addHistory(room, 'Problème signalé : $description');
      addNotification(
        state,
        title: urgent ? 'Maintenance urgente' : 'Maintenance',
        message: 'Chambre ${event.roomNumber} : $description',
        roomNumber: event.roomNumber,
        audience: 'supervisor',
      );
    // The event names only the room: every open report of the room is
    // resolved. The room stays out of service until the supervisor brings
    // it back to cleaning ("Remettre à nettoyer").
    case MaintenanceResolved():
      if (resolveIssues(state, event.roomNumber, mutationNow()) == 0) return;
      final outOfService = room['status'] == 'maintenance';
      addHistory(room, 'Intervention terminée (Maintenance)');
      addNotification(
        state,
        title: 'Maintenance terminée',
        message: outOfService
            ? 'Chambre ${event.roomNumber} : intervention terminée. Remettez-la à nettoyer depuis Signalements.'
            : 'Chambre ${event.roomNumber} : intervention terminée.',
        roomNumber: event.roomNumber,
        audience: 'supervisor',
      );
    case RoomReady() || ExtraCharged():
      return; // Sent by housekeeping, not received.
  }
  bumpVersion(room);
}

// Events have no screen to show an error on: keep the app running and log it.
void _apply(HousekeepingStore store, AppEvent event) => store
    .systemChange((state) => applyHotelEvent(state, event))
    .catchError(
      (Object error) => debugPrint('housekeeping: événement ignoré ($error)'),
    );
