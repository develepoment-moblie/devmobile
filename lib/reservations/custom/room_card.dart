import 'package:flutter/material.dart';

import '../models/room.dart';
import 'app_colors.dart';

class RoomCard extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;

  const RoomCard({
    super.key,
    required this.room,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ROOM IMAGE
            SizedBox(
              width: double.infinity,
              height: 180,
              child: Image.asset(
                room.imagePath,
                fit: BoxFit.cover,

                // Temporary diagnostic:
                errorBuilder: (context, error, stackTrace) {
                  debugPrint(
                    'IMAGE ERROR: ${room.imagePath}',
                  );
                  debugPrint(
                    'ERROR: $error',
                  );

                  return Container(
                    color: AppColors.navy.withOpacity(0.08),
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
                          room.imagePath,
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
            ),

            // ROOM INFORMATION
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          '${room.surface} m² · '
                              '${room.capacity} pers. · '
                              '${room.type}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${room.pricePerNight.toStringAsFixed(0)} €',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),

                      const Text(
                        '/ nuit',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}