import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../widgets/nova_logo.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/placeholder_tab.dart';
import 'tabs/profil_tab.dart';

// ============ PALETTE ============
const _cream      = Color(0xFFF6F1EA);
const _darkGreen  = Color(0xFF1B3A32);
const _greenTop   = Color(0xFF244A3F);
const _terra      = Color(0xFFC4704F);
const _muted      = Color(0xFF8B8378);
const _softGreen  = Color(0xFFE5EDE7);
const _softTerra  = Color(0xFFFBE9E3);
const _greenTxt   = Color(0xFF3E7B5C);

class StaffHome extends StatefulWidget {
  final AppUser user;
  const StaffHome({super.key, required this.user});

  @override
  State<StaffHome> createState() => _StaffHomeState();
}

class _StaffHomeState extends State<StaffHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _tab,
          children: [
            _buildAccueil(),
            const PlaceholderTab(
              icon: Icons.calendar_today_outlined,
              title: 'Réservations',
            ),
            const PlaceholderTab(
              icon: Icons.meeting_room_outlined,
              title: 'Chambres',
            ),
            const PlaceholderTab(
              icon: Icons.room_service_outlined,
              title: 'Services',
            ),
            ProfilTab(user: widget.user),
          ],
        ),
      ),
      bottomNavigationBar: BottomBar(
        current: _tab,
        badgeIndex: 3, // 🔴 sur "Services"
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }

  // ============ ONGLET ACCUEIL ============
  Widget _buildAccueil() {
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== HEADER =====
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  const NovaLogo(size: 36),
                  const Spacer(),
                  const Text(
                    'Espace personnel',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _darkGreen,
                    ),
                  ),
                  const Spacer(),
                  _CircleIcon(
                    icon: Icons.notifications_none,
                    onTap: () {},
                  ),
                  const SizedBox(width: 8),
                  _CircleIcon(
                    icon: Icons.logout,
                    onTap: AuthService.logout,
                  ),
                ],
              ),
            ),
          ),

          // ===== CARTE VERTE =====
          _HeaderCard(firstName: widget.user.firstName),

          const SizedBox(height: 20),

          // ===== STATS =====
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: _StatsRow(
              occupancy: '78%',
              arrivals: 14,
              departures: 8,
            ),
          ),

          const SizedBox(height: 28),

          // ===== ACCÈS RAPIDE =====
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Accès rapide',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _darkGreen,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: _QuickAccessGrid(),
          ),

          const SizedBox(height: 28),

          // ===== PRIORITÉS DU JOUR =====
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Priorités du jour',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _darkGreen,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _PriorityCard(
                  roomNumber: '305',
                  title: "Préparer l'arrivée VIP",
                  subtitle: 'Avant 12h · Assignée à Sarah',
                  badge: 'Urgent',
                  onTap: () {},
                ),
                const SizedBox(height: 10),
                _PriorityCard(
                  icon: Icons.check,
                  title: 'Check-in anticipé',
                  subtitle: 'Madame Martin · 11h30',
                  badge: 'Prêt',
                  onTap: () {},
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

// ============ HEADER CARD VERTE ============
class _HeaderCard extends StatelessWidget {
  final String firstName;
  const _HeaderCard({required this.firstName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_greenTop, _darkGreen],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ESPACE PERSONNEL',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Bonjour $firstName.',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Service du matin · 07:00 – 15:00',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

// ============ STATS ROW ============
class _StatsRow extends StatelessWidget {
  final String occupancy;
  final int arrivals;
  final int departures;
  const _StatsRow({
    required this.occupancy,
    required this.arrivals,
    required this.departures,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _StatItem(value: occupancy, label: 'Occupation'),
          _VDivider(),
          _StatItem(value: '$arrivals', label: 'Arrivées'),
          _VDivider(),
          _StatItem(value: '$departures', label: 'Départs'),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _darkGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
        ],
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: Colors.black.withOpacity(0.06),
    );
  }
}

// ============ GRILLE ACCÈS RAPIDE ============
class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid();

  static const _items = [
    (Icons.calendar_today_outlined,    'Réservations', '14 arrivées'),
    (Icons.meeting_room_outlined,      'Chambres',     '56 occupées'),
    (Icons.auto_awesome_outlined,      'Ménage',       '12 restantes'),
    (Icons.cleaning_services_outlined, 'Maintenance',  '3 actives'),
    (Icons.people_outline,             'Clients',      '48 présents'),
    (Icons.receipt_long_outlined,      'Facturation',  '6 à valider'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.92,
      ),
      itemBuilder: (context, i) {
        final (icon, title, subtitle) = _items[i];
        return _QuickCard(icon: icon, title: title, subtitle: subtitle);
      },
    );
  }
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _QuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(12),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: _softGreen,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: _darkGreen),
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _darkGreen,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 10, color: _muted),
            ),
          ],
        ),
      ),
    );
  }
}

// ============ PRIORITY CARD ============
class _PriorityCard extends StatelessWidget {
  final String? roomNumber;
  final IconData? icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback? onTap;

  const _PriorityCard({
    this.roomNumber,
    this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUrgent = badge?.toLowerCase() == 'urgent';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
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
            if (roomNumber != null)
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isUrgent ? _softTerra : _softGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  roomNumber!,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isUrgent ? _terra : _darkGreen,
                  ),
                ),
              )
            else
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _softGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon ?? Icons.check, size: 24, color: _darkGreen),
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
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11.5, color: _muted),
                  ),
                ],
              ),
            ),

            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isUrgent ? _softTerra : _softGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isUrgent ? _terra : _greenTxt,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isUrgent ? _terra : _greenTxt,
                      ),
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

// ============ ICON BUTTON ROND ============
class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: _darkGreen),
      ),
    );
  }
}