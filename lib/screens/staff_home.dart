import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../widgets/nova_logo.dart';

class StaffHome extends StatelessWidget {
  final AppUser user;
  const StaffHome({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            NovaLogo(size: 28),
            SizedBox(width: 10),
            Text('ESPACE PERSONNEL'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: AuthService.logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Bonjour ${user.firstName}.',
          style: const TextStyle(fontSize: 30),
        ),
      ),
    );
  }
}