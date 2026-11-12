import 'package:flutter/material.dart';

import '../custom/app_colors.dart';
import '../custom/status_chip.dart';
import '../models/reservation.dart';
import '../services/reservation_service.dart';

class MyStaysScreen extends StatelessWidget {
  const MyStaysScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = ReservationService.instance;

    return DefaultTabController(
      length: 3,

      child: Scaffold(
        backgroundColor: AppColors.background,

        appBar: AppBar(
          title: const Text('Mes séjours'),

          bottom: const TabBar(
            labelColor: AppColors.navy,
            indicatorColor: AppColors.gold,

            tabs: [
              Tab(text: 'À venir'),
              Tab(text: 'Passés'),
              Tab(text: 'Annulés'),
            ],
          ),
        ),

        body: ListenableBuilder(
          listenable: service,

          builder: (context, _) {
            final all = service.reservations;

            final upcoming = all
                .where(
                  (r) =>
              r.status ==
                  ReservationStatus.confirmed ||
                  r.status ==
                      ReservationStatus.checkedIn,
            )
                .toList();

            final past = all
                .where(
                  (r) =>
              r.status ==
                  ReservationStatus.checkedOut,
            )
                .toList();

            final cancelled = all
                .where(
                  (r) =>
              r.status ==
                  ReservationStatus.cancelled,
            )
                .toList();

            return TabBarView(
              children: [
                _list(context, upcoming, service),
                _list(context, past, service),
                _list(context, cancelled, service),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _list(
      BuildContext context,
      List<Reservation> items,
      ReservationService service,
      ) {
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'Aucun séjour ici.',
          style: TextStyle(
            color: AppColors.muted,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),

      itemCount: items.length,

      itemBuilder: (context, i) {
        final r = items[i];

        return Card(
          elevation: 0,

          margin: const EdgeInsets.only(
            bottom: 12,
          ),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),

          clipBehavior: Clip.antiAlias,

          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,

            children: [
              // ROOM IMAGE
              Image.asset(
                r.room.imagePath,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,

                errorBuilder: (context, error, stackTrace) {
                  debugPrint(
                    'STAYS IMAGE ERROR: ${r.room.imagePath}',
                  );
                  debugPrint('ERROR: $error');

                  return Container(
                    height: 150,
                    width: double.infinity,
                    color: AppColors.navy.withValues(alpha: 0.08),

                    child: Column(
                      mainAxisAlignment:
                      MainAxisAlignment.center,

                      children: [
                        const Icon(
                          Icons.broken_image_outlined,
                          size: 50,
                          color: AppColors.navy,
                        ),

                        const SizedBox(height: 8),

                        Text(
                          r.room.imagePath,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.navy,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),

              Padding(
                padding: const EdgeInsets.all(16),

                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Row(
                      mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,

                      children: [
                        Expanded(
                          child: Text(
                            r.room.name,

                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight:
                              FontWeight.w600,
                            ),
                          ),
                        ),

                        StatusChip(r.status),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Text(
                      '${r.id} · ${r.guestName}',

                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      '${fmtDate(r.checkIn)} → ${fmtDate(r.checkOut)} · ${r.nights} nuit(s)',
                    ),

                    const SizedBox(height: 6),

                    Text(
                      '${r.total.toStringAsFixed(0)} €',

                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),

                    if (r.status ==
                        ReservationStatus.confirmed ||
                        r.status ==
                            ReservationStatus.checkedIn)
                      ...[
                        const SizedBox(height: 8),

                        Wrap(
                          spacing: 8,

                          children: [
                            if (r.status ==
                                ReservationStatus.confirmed)
                              OutlinedButton(
                                onPressed: () =>
                                    service.checkIn(r.id),

                                child:
                                const Text('Check-in'),
                              ),

                            if (r.status ==
                                ReservationStatus.checkedIn)
                              OutlinedButton(
                                onPressed: () =>
                                    service.checkOut(r.id),

                                child:
                                const Text('Check-out'),
                              ),

                            if (r.status ==
                                ReservationStatus.confirmed)
                              TextButton(
                                onPressed: () =>
                                    _confirmCancel(
                                      context,
                                      service,
                                      r,
                                    ),

                                child: const Text(
                                  'Annuler',

                                  style: TextStyle(
                                    color:
                                    AppColors.danger,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmCancel(
      BuildContext context,
      ReservationService service,
      Reservation reservation,
      ) {
    showDialog(
      context: context,

      builder: (ctx) {
        return AlertDialog(
          title: const Text(
            'Annuler la réservation ?',
          ),

          content: Text(
            '${reservation.room.name} · '
                '${fmtDate(reservation.checkIn)} → '
                '${fmtDate(reservation.checkOut)}',
          ),

          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx),

              child: const Text('Non'),
            ),

            TextButton(
              onPressed: () {
                service.cancel(
                  reservation.id,
                );

                Navigator.pop(ctx);
              },

              child: const Text(
                'Oui, annuler',
              ),
            ),
          ],
        );
      },
    );
  }
}