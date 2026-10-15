import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';

class MaintenanceHome extends StatelessWidget {
  final AppUser user;
  const MaintenanceHome({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MAINTENANCE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: AuthService.logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bonjour ${user.firstName}.',
              style: const TextStyle(fontSize: 14, color: Color(0xFFC4704F)),
            ),
            const SizedBox(height: 8),
            const Text('3 interventions actives',
                style: TextStyle(fontSize: 30)),
          ],
        ),
      ),
    );
  }
}