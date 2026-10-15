import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';

final supabase = Supabase.instance.client;

class AuthService {
  // ============ AUTHENTIFICATION ============

  static Future<void> login(String email, String password) =>
      supabase.auth.signInWithPassword(email: email, password: password);

  static Future<void> register(String email, String password, String name) =>
      supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );

  static Future<void> logout() => supabase.auth.signOut();

  // ============ PROFIL DE L'UTILISATEUR CONNECTÉ ============

  static Future<AppUser> currentProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Aucun utilisateur connecté');
    }

    // 1. Chercher le profil sans throw si absent
    final existing = await supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (existing != null) {
      return AppUser.fromMap(existing);
    }

    // 2. Pas de profil → on le crée (fallback de sécurité)
    final name = (user.userMetadata?['full_name'] as String?) ?? '';
    final inserted = await supabase
        .from('profiles')
        .insert({
      'id': user.id,
      'full_name': name,
      'role': 'guest',
      'points': 0,
    })
        .select()
        .single();

    return AppUser.fromMap(inserted);
  }

  // ============ LISTE + GESTION (MANAGER) ============

  /// Récupère tous les profils (utilisé par le manager)
  static Future<List<AppUser>> allProfiles() async {
    final data = await supabase
        .from('profiles')
        .select()
        .order('full_name', ascending: true);
    return (data as List)
        .map((m) => AppUser.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  /// Change uniquement le rôle d'un utilisateur
  static Future<void> updateRole(String userId, String newRole) async {
    await supabase
        .from('profiles')
        .update({'role': newRole})
        .eq('id', userId);
  }

  /// ✏️ Modifie le nom complet + rôle d'un utilisateur
  static Future<void> updateUser({
    required String userId,
    required String fullName,
    required String role,
  }) async {
    await supabase.from('profiles').update({
      'full_name': fullName,
      'role': role,
    }).eq('id', userId);
  }

  /// ➕ Crée un nouvel utilisateur SANS perdre la session du manager
  ///
  /// ⚠️ Nécessite que le trigger `handle_new_user()` ait été modifié
  /// pour lire `role` depuis `raw_user_meta_data`.
  static Future<void> createUser({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    // 1. 💾 Sauvegarde la session du manager AVANT
    final savedSession = supabase.auth.currentSession;
    final savedRefresh = savedSession?.refreshToken;

    try {
      // 2. Crée le nouvel utilisateur (le trigger crée le profil)
      final res = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'role': role,
        },
      );

      // 3. Force le rôle si le trigger ne l'a pas appliqué correctement
      if (res.user != null) {
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          await supabase.from('profiles').update({
            'full_name': fullName,
            'role': role,
          }).eq('id', res.user!.id);
        } catch (_) {
          // Ignore : le trigger a peut-être déjà mis les bonnes valeurs
        }
      }
    } finally {
      // 4. 🔄 Restaure la session du manager
      if (savedRefresh != null) {
        try {
          await supabase.auth.setSession(savedRefresh);
        } catch (_) {
          // Si la restauration échoue, on laisse l'app se re-login
        }
      }
    }
  }

  /// 🗑️ Supprime un profil
  ///
  /// ⚠️ Ne supprime que la ligne dans `profiles`.
  /// Le compte `auth.users` reste actif. Pour vraiment supprimer,
  /// il faut une Edge Function avec `service_role`.
  static Future<void> deleteProfile(String userId) async {
    await supabase.from('profiles').delete().eq('id', userId);
  }
}