  import 'package:flutter/material.dart';
  import '../models/app_user.dart';
  import '../services/auth_service.dart';

  const _cream     = Color(0xFFF6F1EA);
  const _darkGreen = Color(0xFF1B3A32);
  const _terra     = Color(0xFFC4704F);
  const _muted     = Color(0xFF8B8378);
  const _salmon    = Color(0xFFD98E76);

  class ManageUsersScreen extends StatefulWidget {
    const ManageUsersScreen({super.key});

    @override
    State<ManageUsersScreen> createState() => _ManageUsersScreenState();
  }

  class _ManageUsersScreenState extends State<ManageUsersScreen> {
    static const _roles = ['guest', 'staff', 'manager', 'maintenance', 'admin'];

    late Future<List<AppUser>> _future;

    @override
    void initState() {
      super.initState();
      _future = AuthService.allProfiles();
    }

    void _reload() {
      final future = AuthService.allProfiles();
      setState(() {
        _future = future;
      });
    }

    // ============ ✏️ MODIFIER ============
    Future<void> _editUser(AppUser user) async {
      final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _UserFormSheet(
          title: 'Modifier l\'utilisateur',
          initialName: user.fullName,
          initialRole: user.role,
          isEdit: true,
        ),
      );

      if (result == null) return;

      try {
        await AuthService.updateUser(
          userId: user.id,
          fullName: result['fullName'] as String,
          role: result['role'] as String,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Utilisateur mis à jour.')),
        );
        _reload();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }

    // ============ ➕ AJOUTER ============
    Future<void> _addUser() async {
      final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => const _UserFormSheet(
          title: 'Nouvel utilisateur',
          isEdit: false,
        ),
      );

      if (result == null) return;

      try {
        await AuthService.createUser(
          email: result['email'] as String,
          password: result['password'] as String,
          fullName: result['fullName'] as String,
          role: result['role'] as String,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Utilisateur créé.')),
        );
        _reload();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }

    // ============ 🗑️ SUPPRIMER ============
    Future<void> _deleteUser(AppUser user) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Supprimer cet utilisateur ?'),
          content: Text(
            'Le profil de ${user.fullName.isEmpty ? user.id.substring(0, 8) : user.fullName} '
                'sera supprimé.\n\n'
                '⚠️ Le compte d\'authentification restera actif côté Supabase.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      try {
        await AuthService.deleteProfile(user.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Utilisateur supprimé.')),
        );
        _reload();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }

    // ============ 🔄 CHANGER RÔLE (raccourci) ============
    Future<void> _changeRole(AppUser user, String newRole) async {
      if (user.role == newRole) return;

      try {
        await AuthService.updateRole(user.id, newRole);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.fullName} → $newRole')),
        );
        _reload();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }

    Color _roleColor(String role) {
      switch (role) {
        case 'admin':
          return const Color(0xFF7B2D26);
        case 'manager':
          return const Color(0xFF1B3A32);
        case 'staff':
          return const Color(0xFF3E7B5C);
        case 'maintenance':
          return const Color(0xFFB58B3A);
        default:
          return const Color(0xFFC4704F);
      }
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: _cream,
        appBar: AppBar(
          backgroundColor: _cream,
          elevation: 0,
          iconTheme: const IconThemeData(color: _darkGreen),
          // 👇 Bouton retour explicite + reload au retour
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          title: const Text(
            'GESTION DES UTILISATEURS',
            style: TextStyle(color: _darkGreen, fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _reload,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: _darkGreen,
          foregroundColor: Colors.white,
          onPressed: _addUser,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Ajouter'),
        ),
        body: RefreshIndicator(
          color: _darkGreen,
          onRefresh: () async {
            _reload();
            await _future;
          },
          child: FutureBuilder<List<AppUser>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 100),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Erreur: ${snap.error}'),
                      ),
                    ),
                  ],
                );
              }
              final users = snap.data ?? [];
              if (users.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 100),
                    Center(child: Text('Aucun utilisateur.')),
                  ],
                );
              }

              return ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: users.length,
                itemBuilder: (context, i) {
                  final u = users[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        leading: CircleAvatar(
                          backgroundColor: _roleColor(u.role),
                          child: Text(
                            u.firstName.isNotEmpty
                                ? u.firstName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          u.fullName.isEmpty ? '(sans nom)' : u.fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _darkGreen,
                          ),
                        ),
                        subtitle: Text(
                          u.role,
                          style: TextStyle(
                            color: _roleColor(u.role),
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: _darkGreen),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onSelected: (val) {
                            switch (val) {
                              case 'edit':
                                _editUser(u);
                                break;
                              case 'delete':
                                _deleteUser(u);
                                break;
                              default:
                                if (val.startsWith('role:')) {
                                  _changeRole(u, val.substring(5));
                                }
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 18),
                                  SizedBox(width: 10),
                                  Text('Modifier'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline,
                                      size: 18, color: Colors.redAccent),
                                  SizedBox(width: 10),
                                  Text('Supprimer',
                                      style:
                                      TextStyle(color: Colors.redAccent)),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            ..._roles.map((r) => PopupMenuItem(
                              value: 'role:$r',
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: _roleColor(r),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('Passer en "$r"'),
                                ],
                              ),
                            )),
                          ],
                        ),
                        onTap: () => _editUser(u),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      );
    }
  }

  // ============ FORMULAIRE (AJOUT / MODIF) ============
  class _UserFormSheet extends StatefulWidget {
    final String title;
    final bool isEdit;
    final String? initialName;
    final String? initialRole;

    const _UserFormSheet({
      required this.title,
      required this.isEdit,
      this.initialName,
      this.initialRole,
    });

    @override
    State<_UserFormSheet> createState() => _UserFormSheetState();
  }

  class _UserFormSheetState extends State<_UserFormSheet> {
    static const _roles = ['guest', 'staff', 'manager', 'maintenance', 'admin'];

    late final TextEditingController _nameCtrl;
    late final TextEditingController _emailCtrl;
    late final TextEditingController _passCtrl;
    String _role = 'guest';
    bool _obscure = true;

    @override
    void initState() {
      super.initState();
      _nameCtrl = TextEditingController(text: widget.initialName ?? '');
      _emailCtrl = TextEditingController();
      _passCtrl = TextEditingController();
      _role = _roles.contains(widget.initialRole)
          ? widget.initialRole!
          : 'guest';
    }

    @override
    void dispose() {
      _nameCtrl.dispose();
      _emailCtrl.dispose();
      _passCtrl.dispose();
      super.dispose();
    }

    void _submit() {
      if (_nameCtrl.text.trim().isEmpty) {
        _snack('Renseigne le nom complet.');
        return;
      }
      if (!widget.isEdit) {
        if (_emailCtrl.text.trim().isEmpty || !_emailCtrl.text.contains('@')) {
          _snack('Renseigne un e-mail valide.');
          return;
        }
        if (_passCtrl.text.length < 6) {
          _snack('Mot de passe : 6 caractères minimum.');
          return;
        }
      }

      Navigator.pop(context, {
        'fullName': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'password': _passCtrl.text,
        'role': _role,
      });
    }

    void _snack(String msg) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }

    @override
    Widget build(BuildContext context) {
      final bottom = MediaQuery.of(context).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _darkGreen,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom complet',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              if (!widget.isEdit) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'Rôle',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _roles.map((r) {
                  final selected = r == _role;
                  return ChoiceChip(
                    label: Text(r),
                    selected: selected,
                    onSelected: (_) => setState(() => _role = r),
                    selectedColor: _darkGreen,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : _darkGreen,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: _cream,
                    side: BorderSide(
                      color: selected ? _darkGreen : Colors.black12,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
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
                  onPressed: _submit,
                  child: Text(
                    widget.isEdit ? 'Enregistrer' : 'Créer l\'utilisateur',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }