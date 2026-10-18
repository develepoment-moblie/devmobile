import 'package:flutter/material.dart';

import '../shared/custom/app_theme.dart';
import '../shared/custom/app_widgets.dart';
import '../shared/custom/nova_logo.dart';
import '../housekeeping/models/hotel_data.dart';

class ProfileScreen extends StatefulWidget {
  final HotelData data;
  final VoidCallback onHousekeeping;
  const ProfileScreen({
    super.key,
    required this.data,
    required this.onHousekeeping,
  });
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 7, 18, 24),
    children: [
      const Center(child: NovaLogo(size: 180)),
      const SizedBox(height: 16),
      StaffBanner(
        title: widget.data.currentUser,
        label: 'MON ESPACE PERSONNEL',
      ),
      const SizedBox(height: 24),
      const Text(
        'Service du matin',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        '07:00 — 15:00 · Nova Paris',
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 24),
      if (!widget.data.isConnected)
        const Text(
          'Rôle de démonstration',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      const SizedBox(height: 8),
      if (!widget.data.isConnected)
        const Text(
          'Les données sont locales. Le choix du rôle permet de tester la validation du nettoyage sans connexion.',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      const SizedBox(height: 16),
      if (widget.data.isConnected)
        Text(
          widget.data.isSupervisor
              ? 'Gouvernante · session vérifiée par le serveur'
              : 'Agent d’étage · session vérifiée par le serveur',
        ),
      if (!widget.data.isConnected)
        DropdownButtonFormField<bool>(
          isExpanded: true,
          initialValue: widget.data.isSupervisor,
          decoration: const InputDecoration(labelText: 'Profil actif'),
          items: const [
            DropdownMenuItem(
              value: false,
              child: Text('Sarah · Agent d’étage'),
            ),
            DropdownMenuItem(value: true, child: Text('Amina · Gouvernante')),
          ],
          onChanged: (value) => setState(() {
            widget.data.isSupervisor = value!;
            widget.data.currentUser = value ? 'Amina' : 'Sarah';
          }),
        ),
      const SizedBox(height: 24),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.cleaning_services_outlined),
        title: const Text('Ménage'),
        subtitle: Text('${widget.data.remaining} chambres restantes'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.onHousekeeping,
      ),
    ],
  );
}
