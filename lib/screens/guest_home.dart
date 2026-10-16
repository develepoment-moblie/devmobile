import 'package:flutter/material.dart';
import '../main.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../widgets/nova_logo.dart';

// ============ PALETTE ============
const _cream      = Color(0xFFF6F1EA);
const _darkGreen  = Color(0xFF1B3A32);
const _terra      = Color(0xFFC4704F);
const _salmon     = Color(0xFFD98E76);
const _cardBeige  = Color(0xFFFBF7F0);
const _muted      = Color(0xFF8B8378);

class GuestHome extends StatelessWidget {
  final AppUser user;
  const GuestHome({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(user: user),
              const SizedBox(height: 24),
              _Greeting(user: user),
              const SizedBox(height: 20),
              const _CategoriesRow(),
              const SizedBox(height: 24),
              const _HeroCard(),
              const SizedBox(height: 24),
              const _SearchCard(),
              const SizedBox(height: 32),
              _SectionHeader(
                title: 'Expériences à vivre',
                onTap: () {},
              ),
              const SizedBox(height: 12),
              const _ExperiencesRow(),
            ],
          ),
        ),
      ),
    );
  }
}

// ============ HEADER ============
class _Header extends StatelessWidget {
  final AppUser user;
  const _Header({required this.user});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const NovaLogo(size: 40),
        const SizedBox(width: 10),
        const Text(
          'NOVA PARIS',
          style: TextStyle(
            fontSize: 14,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
            color: _darkGreen,
          ),
        ),
        const Spacer(),
        _CircleIconButton(
          icon: Icons.notifications_none,
          onTap: () {},
        ),
        const SizedBox(width: 8),
        _CircleIconButton(
          icon: Icons.logout,
          onTap: () async {
            await AuthService.logout();
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthGate()),
                  (route) => false,
            );
          },
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

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

// ============ GREETING ============
class _Greeting extends StatelessWidget {
  final AppUser user;
  const _Greeting({required this.user});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BONJOUR ${user.firstName.toUpperCase()}',
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
            color: _terra,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Votre escapade\ncommence ici.',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w500,
            color: _darkGreen,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

// ============ CATEGORIES ============
class _CategoriesRow extends StatelessWidget {
  const _CategoriesRow();

  static const _items = [
    ('Offres', Icons.local_offer_outlined, true),
    ('Spa', Icons.spa_outlined, false),
    ('Restaurant', Icons.restaurant_outlined, false),
    ('Nouveautés', Icons.auto_awesome_outlined, false),
    ('Événements', Icons.celebration_outlined, false),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final (label, icon, selected) = _items[i];
          return Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? _terra : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: selected
                          ? [const Color(0xFFE8C9A0), const Color(0xFFB58B6A)]
                          : [const Color(0xFFEFE7DA), const Color(0xFFD9CBB6)],
                    ),
                  ),
                  child: Icon(icon, size: 22, color: _darkGreen),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? _darkGreen : _muted,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============ HERO CARD ============
class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 11,
            child: Image.network(
              'https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=800',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: _darkGreen),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _cream,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: const [
                  Icon(Icons.star, size: 12, color: _terra),
                  SizedBox(width: 4),
                  Text(
                    'OFFRE EXCLUSIVE',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                      color: _darkGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Paris, autrement.',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Un refuge contemporain au cœur de la ville.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============ SEARCH CARD ============
class _SearchCard extends StatefulWidget {
  const _SearchCard();

  @override
  State<_SearchCard> createState() => _SearchCardState();
}

class _SearchCardState extends State<_SearchCard> {
  DateTime? _arrival;
  DateTime? _departure;
  int _guests = 2;

  static const _moisFr = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];

  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day} ${_moisFr[d.month - 1]}';
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
      initialDateRange: (_arrival != null && _departure != null)
          ? DateTimeRange(start: _arrival!, end: _departure!)
          : null,
      helpText: 'Sélectionne tes dates',
      saveText: 'Valider',
      cancelText: 'Annuler',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _darkGreen,
              onPrimary: Colors.white,
              onSurface: _darkGreen,
            ),
          ),
          child: child!,
        );
      },
    );

    if (range != null) {
      setState(() {
        _arrival = range.start;
        _departure = range.end;
      });
    }
  }

  Future<void> _pickGuests() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _GuestsSheet(initial: _guests),
    );
    if (result != null) setState(() => _guests = result);
  }

  void _search() {
    if (_arrival == null || _departure == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Choisis d'abord tes dates.")),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Recherche : ${_formatDate(_arrival)} → ${_formatDate(_departure)} · $_guests pers.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: 'ARRIVÉE',
                  value: _formatDate(_arrival),
                  icon: Icons.calendar_today_outlined,
                  onTap: _pickRange,
                ),
              ),
              Expanded(
                child: _DateField(
                  label: 'DÉPART',
                  value: _formatDate(_departure),
                  icon: Icons.calendar_today_outlined,
                  onTap: _pickRange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: _DateField(
              label: 'VOYAGEURS',
              value: '$_guests pers.',
              icon: Icons.people_outline,
              onTap: _pickGuests,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _salmon,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              onPressed: _search,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    'Rechercher',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.search, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============ DATE FIELD ============
class _DateField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: _darkGreen),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _darkGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============ SECTION HEADER ============
class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  const _SectionHeader({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _darkGreen,
          ),
        ),
        TextButton(
          onPressed: onTap,
          child: const Row(
            children: [
              Text('Tout voir', style: TextStyle(color: _terra, fontSize: 12)),
              SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 16, color: _terra),
            ],
          ),
        ),
      ],
    );
  }
}

// ============ EXPERIENCES ROW ============
class _ExperiencesRow extends StatelessWidget {
  const _ExperiencesRow();

  static const _experiences = [
    (
    'Dîner aux chandelles',
    'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=400',
    ),
    (
    'Spa & Détente',
    'https://images.unsplash.com/photo-1540555700478-4be289fbecef?w=400',
    ),
    (
    'Balade en Seine',
    'https://images.unsplash.com/photo-1499856871958-5b9627545d1a?w=400',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _experiences.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final (title, url) = _experiences[i];
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 220,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: _cardBeige),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.6),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============ GUESTS BOTTOM SHEET ============
class _GuestsSheet extends StatefulWidget {
  final int initial;
  const _GuestsSheet({required this.initial});

  @override
  State<_GuestsSheet> createState() => _GuestsSheetState();
}

class _GuestsSheetState extends State<_GuestsSheet> {
  late int _count;

  @override
  void initState() {
    super.initState();
    _count = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Voyageurs',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _darkGreen,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text(
                  'Nombre de personnes',
                  style: TextStyle(fontSize: 15, color: _darkGreen),
                ),
                const Spacer(),
                _RoundBtn(
                  icon: Icons.remove,
                  onTap: _count > 1 ? () => setState(() => _count--) : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '$_count',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _darkGreen,
                    ),
                  ),
                ),
                _RoundBtn(
                  icon: Icons.add,
                  onTap: _count < 20 ? () => setState(() => _count++) : null,
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _salmon,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(context, _count),
                child: const Text(
                  'Valider',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled ? _darkGreen : Colors.black12,
            width: 1.5,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? _darkGreen : Colors.black26,
        ),
      ),
    );
  }
}