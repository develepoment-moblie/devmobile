import 'package:flutter/material.dart';

import '../../shared/custom/app_theme.dart';
import '../../shared/custom/app_widgets.dart';
import '../../shared/custom/draft_guard.dart';
import '../models/app_user.dart';
import '../services/user_repository.dart';

// Adapted from the friend's user list and form sheet, with confirmed remote saves.
class ManageUsersScreen extends StatefulWidget {
  final UserRepository auth;
  const ManageUsersScreen({super.key, required this.auth});
  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  late Future<List<AppUser>> future;
  final query = TextEditingController();
  bool deleting = false;
  String? error;
  @override
  void initState() {
    super.initState();
    future = widget.auth.allProfiles();
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    final next = widget.auth.allProfiles();
    setState(() {
      future = next;
    });
    try {
      await future;
    } catch (_) {
      /* FutureBuilder displays recovery. */
    }
  }

  Future<void> form([AppUser? user]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => UserFormSheet(auth: widget.auth, user: user),
    );
    if (!mounted || saved != true) return;
    showFeedback(
      context,
      user == null ? 'Utilisateur créé.' : 'Utilisateur mis à jour.',
    );
    await reload();
  }

  Future<void> remove(AppUser user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Supprimer ce profil ?'),
        content: Text(
          'Le profil de ${user.fullName} sera supprimé et son accès à l’application sera retiré. Ses références historiques seront conservées sur cet appareil.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer le profil'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      deleting = true;
      error = null;
    });
    try {
      await widget.auth.deleteProfile(user);
      if (mounted) {
        showFeedback(context, 'Profil supprimé.');
        await reload();
      }
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Utilisateurs'),
      actions: [
        IconButton(
          tooltip: 'Actualiser',
          onPressed: deleting ? null : reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: deleting ? null : () => form(),
      icon: const Icon(Icons.person_add_alt_1),
      label: const Text('Ajouter'),
    ),
    body: Column(
      children: [
        if (deleting) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(18),
            child: Text(error!, style: const TextStyle(color: AppColors.red)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
          child: TextField(
            controller: query,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Rechercher un utilisateur',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer la recherche',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(query.clear),
                    ),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AppUser>>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(userError(snap.error!)),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: reload,
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final term = query.text.trim().toLowerCase();
              final users = (snap.data ?? [])
                  .where(
                    (u) =>
                        u.fullName.toLowerCase().contains(term) ||
                        u.roleLabel.toLowerCase().contains(term),
                  )
                  .toList();
              return RefreshIndicator(
                onRefresh: reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 100),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (users.isEmpty)
                      EmptyState(
                        term.isEmpty
                            ? 'Aucun utilisateur'
                            : 'Aucun utilisateur trouvé',
                        term.isEmpty
                            ? 'Ajoutez un profil à votre équipe.'
                            : 'Modifiez ou effacez votre recherche.',
                      ),
                    ...users.map(
                      (user) => Card(
                        color: Colors.white,
                        elevation: 0,
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            child: Text(
                              user.firstName.characters.first.toUpperCase(),
                            ),
                          ),
                          title: Text(
                            user.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(user.roleLabel),
                          onTap: deleting ? null : () => form(user),
                          trailing: PopupMenuButton<String>(
                            enabled: !deleting,
                            tooltip: 'Actions pour ${user.fullName}',
                            onSelected: (action) =>
                                action == 'edit' ? form(user) : remove(user),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Modifier'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Supprimer le profil'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class UserFormSheet extends StatefulWidget {
  final UserRepository auth;
  final AppUser? user;
  const UserFormSheet({super.key, required this.auth, this.user});
  @override
  State<UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends State<UserFormSheet> {
  final key = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.user?.fullName ?? '');
  final email = TextEditingController(), password = TextEditingController();
  late String role = widget.user?.role ?? 'guest';
  bool busy = false, obscure = true;
  String? error;
  bool get dirty =>
      name.text != (widget.user?.fullName ?? '') ||
      email.text.isNotEmpty ||
      password.text.isNotEmpty ||
      role != (widget.user?.role ?? 'guest');
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !key.currentState!.validate()) return;
    if (widget.user != null && widget.user!.role != role) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Changer les autorisations ?'),
          content: Text(
            '${name.text.trim()} aura le rôle ${AppUser.roleLabels[role]}. Ses accès seront modifiés immédiatement.',
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Changer le rôle'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.user == null) {
        await widget.auth.createUser(
          email.text.trim(),
          password.text,
          name.text.trim(),
          role,
        );
      } else {
        await widget.auth.updateUser(widget.user!, name.text.trim(), role);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DraftGuard(
    dirty: dirty,
    busy: busy,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: key,
        onChanged: () => setState(() {}),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.user == null
                  ? 'Nouvel utilisateur'
                  : 'Modifier l’utilisateur',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    style: const TextStyle(color: AppColors.red),
                  ),
                ),
              ),
            TextFormField(
              controller: name,
              enabled: !busy,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nom complet'),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Renseignez le nom complet.'
                  : null,
            ),
            const SizedBox(height: 16),
            if (widget.user == null) ...[
              TextFormField(
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
                validator: (v) =>
                    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                        .hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Renseignez un e-mail valide.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: password,
                enabled: !busy,
                obscureText: obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Mot de passe initial',
                  helperText: '6 caractères minimum',
                  suffixIcon: IconButton(
                    tooltip: obscure
                        ? 'Afficher le mot de passe'
                        : 'Masquer le mot de passe',
                    onPressed: () => setState(() => obscure = !obscure),
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (v) => v == null || v.length < 6
                    ? 'Utilisez au moins 6 caractères.'
                    : null,
              ),
              const SizedBox(height: 16),
            ],
            DropdownButtonFormField<String>(
              initialValue: role,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Rôle'),
              items: AppUser.roleLabels.entries
                  .map(
                    (r) => DropdownMenuItem(value: r.key, child: Text(r.value)),
                  )
                  .toList(),
              onChanged: busy ? null : (value) => setState(() => role = value!),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: busy ? null : save,
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.user == null
                            ? 'Créer l’utilisateur'
                            : 'Enregistrer',
                      ),
              ),
            ),
            TextButton(
              onPressed: busy ? null : () => Navigator.maybePop(context),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    ),
  );
}
