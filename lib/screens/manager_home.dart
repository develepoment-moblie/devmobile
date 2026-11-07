import 'package:flutter/material.dart';
import '../main.dart';
import '../models/app_user.dart';
import '../models/priority.dart';
import '../services/auth_service.dart';
import '../services/database_helper.dart';
import '../utils/icon_mapper.dart';
import '../widgets/nova_logo.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/placeholder_tab.dart';
import 'manage_users.dart';
import 'manage_priorities.dart';
import 'tabs/profil_tab.dart';

// ============ PALETTE ============
const _cream      = Color(0xFFF6F1EA);
const _darkGreen  = Color(0xFF1B3A32);
const _terra      = Color(0xFFC4704F);
const _cardWhite  = Color(0xFFFFFFFF);
const _muted      = Color(0xFF8B8378);
const _success    = Color(0xFFE8F0DC);
const _successTxt = Color(0xFF4A6B3E);
const _danger     = Color(0xFFE8B0A0);
const _dangerTxt  = Color(0xFFB5423A);

class ManagerHome extends StatefulWidget {
  final AppUser user;
  const ManagerHome({super.key, required this.user});

  @override
  State<ManagerHome> createState() => _ManagerHomeState();
}

class _ManagerHomeState extends State<ManagerHome> {
  int _tab = 0;
  static const int? _badgeIndex = 3;

  late Future<List<Priority>> _prioritiesFuture;
  late Future<List<Map<String, dynamic>>> _statsFuture;

  static const _jours = [
    'LUNDI', 'MARDI', 'MERCREDI', 'JEUDI',
    'VENDREDI', 'SAMEDI', 'DIMANCHE',
  ];
  static const _mois = [
    'JANVIER', 'FÉVRIER', 'MARS', 'AVRIL', 'MAI', 'JUIN',
    'JUILLET', 'AOÛT', 'SEPTEMBRE', 'OCTOBRE', 'NOVEMBRE', 'DÉCEMBRE',
  ];

  String get _dateAujourdhui {
    final now = DateTime.now();
    return '${_jours[now.weekday - 1]} ${now.day} ${_mois[now.month - 1]}';
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _prioritiesFuture = DatabaseHelper.instance
        .getAllPriorities()
        .then((rows) => rows.map((m) => Priority.fromMap(m)).toList());
    _statsFuture = DatabaseHelper.instance.getAllStats();
  }

  Future<void> _openManagePriorities() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ManagePrioritiesScreen(),
      ),
    );
    _reload();
    if (mounted) setState(() {});
  }

  // ============ LOGOUT ============
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Déconnexion',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _darkGreen,
          ),
        ),
        content: const Text(
          'Voulez-vous vraiment vous déconnecter ?',
          style: TextStyle(fontSize: 13, color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Annuler',
              style: TextStyle(color: _muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Déconnexion',
              style: TextStyle(
                color: _dangerTxt,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    // Show a loading indicator while logging out
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: _darkGreen),
      ),
    );

    try {
      await AuthService.logout();
    } catch (_) {
      // Ignore: we still navigate out to be safe.
    }

    if (!mounted) return;
    // Close the loading dialog
    Navigator.of(context, rootNavigator: true).pop();

    // Replace entire stack with the auth gate
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
    );
  }

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
        badgeIndex: _badgeIndex,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }

  Widget _buildAccueil() {
    final title =
    widget.user.role == 'admin' ? 'ESPACE ADMIN' : 'ESPACE MANAGER';

    return RefreshIndicator(
      color: _darkGreen,
      onRefresh: () async {
        _reload();
        await _prioritiesFuture;
        await _statsFuture;
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== HEADER =====
            Row(
              children: [
                const NovaLogo(size: 40),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NOVA PARIS',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _darkGreen,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _CircleIcon(icon: Icons.notifications_none, onTap: () {}),
                const SizedBox(width: 8),
                _CircleIcon(
                  icon: Icons.logout,
                  onTap: _handleLogout,
                ),
              ],
            ),
            const SizedBox(height: 24),

            Text(
              _dateAujourdhui,
              style: const TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
            ),
            const SizedBox(height: 8),

            // ===== SALUTATION =====
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bonjour ${widget.user.firstName},',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: _darkGreen,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "L'hôtel est prêt pour la journée.",
                        style: TextStyle(fontSize: 13, color: _muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _AvatarBadge(name: widget.user.firstName),
              ],
            ),
            const SizedBox(height: 20),

            // ===== STATUT =====
            const _StatusCard(
              icon: Icons.auto_awesome,
              title: '83% des chambres prêtes',
              subtitle: '4 chambres avant 15h',
            ),
            const SizedBox(height: 12),

            // ===== STATS DYNAMIQUES =====
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _statsFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 90,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final stats = snap.data ?? [];
                if (stats.isEmpty) {
                  return const SizedBox(height: 90);
                }
                return Row(
                  children: [
                    for (int i = 0; i < stats.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: stats[i]['label'] as String,
                          value: stats[i]['value'] as String,
                          delta: stats[i]['delta'] as String,
                          deltaUp: (stats[i]['delta_up'] as int) == 1,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 28),

            // ===== PRIORITÉS =====
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Priorités',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _darkGreen,
                  ),
                ),
                TextButton(
                  onPressed: _openManagePriorities,
                  child: const Text(
                    'Tout voir',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            FutureBuilder<List<Priority>>(
              future: _prioritiesFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Aucune priorité pour le moment.',
                      style: TextStyle(color: _muted),
                    ),
                  );
                }
                return Column(
                  children: items.map((p) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PriorityTile(
                        icon: iconFromString(p.icon),
                        title: p.title,
                        subtitle: p.subtitle,
                        iconColor: _priorityTextColor(p.colorType),
                        iconBg: _priorityBgColor(p.colorType),
                        onTap: _openManagePriorities,
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 28),

            // ===== BOUTON GÉRER UTILISATEURS =====
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _darkGreen,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.people_alt_outlined),
              label: const Text('Gérer les utilisateurs'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ManageUsersScreen(),
                  ),
                );
              },
            ),

            const SizedBox(height: 12),

            // ===== BOUTON GÉRER PRIORITÉS =====
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _terra,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.priority_high_rounded),
              label: const Text('Gérer les priorités'),
              onPressed: _openManagePriorities,
            ),
          ],
        ),
      ),
    );
  }

  Color _priorityBgColor(String type) {
    switch (type) {
      case 'danger':
        return _danger;
      case 'terra':
        return const Color(0xFFF0E0D5);
      default:
        return const Color(0xFFE5E9DD);
    }
  }

  Color _priorityTextColor(String type) {
    switch (type) {
      case 'danger':
        return _dangerTxt;
      case 'terra':
        return _terra;
      default:
        return _darkGreen;
    }
  }
}

// ============ STATUT CARD ============
class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _success,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: _successTxt),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _darkGreen,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: _successTxt),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: _darkGreen),
        ],
      ),
    );
  }
}

// ============ STAT CARD ============
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String delta;
  final bool deltaUp;
  const _StatCard({
    required this.label,
    required this.value,
    required this.delta,
    required this.deltaUp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _darkGreen,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                deltaUp ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: deltaUp ? _successTxt : _dangerTxt,
              ),
              const SizedBox(width: 2),
              Text(
                delta,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: deltaUp ? _successTxt : _dangerTxt,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============ PRIORITY TILE ============
class _PriorityTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final Color iconBg;
  final VoidCallback onTap;

  const _PriorityTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.iconBg,
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
          color: _cardWhite,
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: iconColor),
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
                      fontWeight: FontWeight.w600,
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

// ============ AVATAR ============
class _AvatarBadge extends StatelessWidget {
  final String name;
  const _AvatarBadge({required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = name.isNotEmpty
        ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase()
        : 'A';
    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        color: Color(0xFFE8C9A0),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: _darkGreen,
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
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: _darkGreen),
      ),
    );
  }
}