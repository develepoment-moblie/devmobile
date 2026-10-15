import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

const _darkGreen = Color(0xFF1B3A32);
const _terra     = Color(0xFFC4704F);
const _muted     = Color(0xFF8B8378);

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // 1. Validations
    if (_pass.text.length < 6) {
      _snack('Mot de passe : 6 caractères minimum.');
      return;
    }
    if (_pass.text != _confirm.text) {
      _snack('Les deux mots de passe ne correspondent pas.');
      return;
    }

    setState(() => _loading = true);

    try {
      // 2. Mise à jour du mot de passe (l'user est déjà "connecté" via le lien)
      await supabase.auth.updateUser(
        UserAttributes(password: _pass.text),
      );

      if (!mounted) return;

      // 3. Message de succès
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mot de passe modifié avec succès !'),
          backgroundColor: _darkGreen,
        ),
      );


      await AuthService.logout();

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Erreur : $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F1EA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icône cadenas
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _darkGreen.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_reset,
                    size: 40,
                    color: _darkGreen,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'Nouveau mot de passe',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _darkGreen,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choisis un mot de passe sécurisé.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _muted),
              ),
              const SizedBox(height: 32),

              // Champ 1
              TextField(
                controller: _pass,
                obscureText: _obscure1,
                decoration: InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure1
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscure1 = !_obscure1),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Champ 2
              TextField(
                controller: _confirm,
                obscureText: _obscure2,
                decoration: InputDecoration(
                  labelText: 'Confirmer le mot de passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure2
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscure2 = !_obscure2),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Bouton
              SizedBox(
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _darkGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Text(
                    'Modifier le mot de passe',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Retour au login
              TextButton(
                onPressed: _loading
                    ? null
                    : () async {
                  await AuthService.logout();
                  if (!context.mounted) return;
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/', (r) => false);
                },
                child: const Text(
                  'Annuler',
                  style: TextStyle(color: _terra),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}