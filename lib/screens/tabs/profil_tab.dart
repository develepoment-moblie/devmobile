import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../login_screen.dart'; // <-- Import login screen

// ============ PALETTE ============
const _cream     = Color(0xFFF6F1EA);
const _darkGreen = Color(0xFF1B3A32);
const _terra     = Color(0xFFC4704F);
const _muted     = Color(0xFF8B8378);
const _softGreen = Color(0xFFE5EDE7);
const _softGold  = Color(0xFFF2E9D0);

class ProfilTab extends StatelessWidget {
  final AppUser user;
  const ProfilTab({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                _AvatarBig(name: user.firstName),
                const SizedBox(height: 14),
                Text(
                  user.fullName.isEmpty ? 'Utilisateur' : user.fullName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _darkGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${user.firstName.toLowerCase()}@novaparis.com',
                  style: const TextStyle(fontSize: 13, color: _muted),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: _softGold,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.star, size: 12, color: _terra),
                      SizedBox(width: 4),
                      Text(
                        'MEMBRE SILVER',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color: _darkGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Divider(color: Colors.black.withOpacity(0.06), height: 1),
          const SizedBox(height: 24),
          Row(
            children: [
              const _MiniStat(value: '3', label: 'Séjours'),
              _MiniDivider(),
              const _MiniStat(value: '4', label: 'Favoris'),
              _MiniDivider(),
              _MiniStat(value: '${user.points}', label: 'Points'),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'Mon espace client',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _darkGreen,
            ),
          ),
          const SizedBox(height: 12),
          _MenuTile(
            icon: Icons.calendar_today_outlined,
            title: 'Mes réservations',
            subtitle: '1 séjour à venir',
            onTap: () {},
          ),
          const SizedBox(height: 10),
          _MenuTile(
            icon: Icons.favorite_border,
            title: 'Mes favoris',
            subtitle: '4 chambres enregistrées',
            onTap: () {},
          ),
          const SizedBox(height: 10),
          _MenuTile(
            icon: Icons.credit_card,
            title: 'Moyens de paiement',
            subtitle: 'Visa •••• 4821',
            onTap: () {},
          ),
          const SizedBox(height: 10),
          _MenuTile(
            icon: Icons.notifications_none,
            title: 'Notifications',
            subtitle: 'Activées',
            onTap: () {},
          ),
          const SizedBox(height: 10),
          _MenuTile(
            icon: Icons.person_outline,
            title: 'Informations personnelles',
            subtitle: 'Profil complété',
            onTap: () {},
          ),
          const SizedBox(height: 32),
          const Text(
            "Changer d'espace",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _darkGreen,
            ),
          ),
          const SizedBox(height: 12),
          _RoleSwitchTile(
            icon: Icons.admin_panel_settings_outlined,
            title: user.role == 'staff' ? 'Espace personnel' : 'Espace manager',
            subtitle: user.role == 'staff'
                ? 'Opérations de l\'hôtel'
                : 'Vue d\'ensemble',
            roleLabel: user.role == 'staff' ? 'Personnel' : 'Manager',
            onTap: () {},
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _terra,
                side: BorderSide(color: _terra.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text(
                'Se déconnecter',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onPressed: () async {
                // 1. Await the logout to clear SharedPreferences
                await AuthService.logout();

                // 2. Check if context is still mounted
                if (!context.mounted) return;

                // 3. Navigate to LoginScreen and remove all previous routes
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (route) => false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ... REST OF YOUR WIDGETS (_AvatarBig, _MiniStat, _MiniDivider, _MenuTile, _RoleSwitchTile) ...
// (Keep them exactly as you had them, no changes needed below this point)
class _AvatarBig extends StatelessWidget {
  final String name;
  const _AvatarBig({required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = name.isNotEmpty
        ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase()
        : 'A';
    return Container(
      width: 92,
      height: 92,
      decoration: const BoxDecoration(
        color: Color(0xFFE8C9A0),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: _darkGreen,
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  const _MiniStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _darkGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        ],
      ),
    );
  }
}

class _MiniDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: Colors.black.withOpacity(0.06),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: _softGreen,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: _darkGreen),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _darkGreen,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: _muted),
          ],
        ),
      ),
    );
  }
}

class _RoleSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String roleLabel;
  final VoidCallback onTap;

  const _RoleSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.roleLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _darkGreen.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: _softGreen,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: _darkGreen),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _darkGreen,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _softGold,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                roleLabel,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _terra,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 20, color: _muted),
          ],
        ),
      ),
    );
  }
}