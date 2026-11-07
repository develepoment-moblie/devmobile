import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/nova_logo.dart';
import '../main.dart';
import 'forgot_password_screen.dart';

const _darkGreen = Color(0xFF1B3A32);
const _muted = Color(0xFF8B8378);
const _cream = Color(0xFFF6F1EA);
const _dangerTxt = Color(0xFFB5423A);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();

  bool _isRegister = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _pass.text.isEmpty) {
      _snack('Remplis tous les champs.');
      return;
    }
    if (_isRegister && _name.text.trim().isEmpty) {
      _snack('Remplis ton nom complet.');
      return;
    }

    setState(() => _loading = true);
    try {
      if (_isRegister) {
        final success = await AuthService.register(
          fullName: _email.text.trim(),
          displayName: _name.text.trim(),
          password: _pass.text,
          role: 'guest',
        );

        if (!mounted) return;

        if (success) {
          _snack('Compte créé. Connexion...');
          final user = await AuthService.login(
            _email.text.trim(),
            _pass.text,
          );
          if (user != null && mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const AuthGate()),
            );
          }
        } else {
          _snack('Cet email est déjà utilisé.');
        }
      } else {
        final user = await AuthService.login(
          _email.text.trim(),
          _pass.text,
        );

        if (!mounted) return;

        if (user != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AuthGate()),
          );
        } else {
          _snack('Email ou mot de passe incorrect.');
        }
      }
    } catch (e) {
      if (mounted) _snack('Erreur: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===== GOOGLE LOGIN =====
  Future<void> _loginWithGoogle() async {
    setState(() => _loading = true);
    try {
      final user = await AuthService.signInWithGoogle();
      if (!mounted) return;
      if (user != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AuthGate()),
        );
      } else {
        _snack('Connexion Google annulée.');
      }
    } catch (e) {
      if (mounted) _snack('Erreur Google: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _dangerTxt),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              const NovaLogo(size: 120, circular: false),
              const SizedBox(height: 16),
              const Text(
                'NOVA PARIS',
                style: TextStyle(
                  fontSize: 22,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600,
                  color: _darkGreen,
                ),
              ),
              const SizedBox(height: 32),

              if (_isRegister) ...[
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Nom complet',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),

              // ===== MOT DE PASSE OUBLIÉ =====
              if (!_isRegister)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ForgotPasswordScreen(),
                      ),
                    ),
                    child: const Text(
                      'Mot de passe oublié ?',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _darkGreen,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
                      : Text(_isRegister ? 'Créer un compte' : 'Se connecter'),
                ),
              ),

              TextButton(
                onPressed: _loading
                    ? null
                    : () => setState(() {
                  _isRegister = !_isRegister;
                }),
                child: Text(
                  _isRegister ? "J'ai déjà un compte" : 'Créer un compte',
                ),
              ),

              // ===== SOCIAL LOGIN =====
              const SizedBox(height: 20),
              const Row(
                children: [
                  Expanded(child: Divider(color: _muted)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('OU', style: TextStyle(color: _muted, fontSize: 12)),
                  ),
                  Expanded(child: Divider(color: _muted)),
                ],
              ),
              const SizedBox(height: 20),

              // Google Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    side: const BorderSide(color: _muted),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.g_mobiledata, size: 32, color: Colors.red),
                  label: const Text(
                    'Continuer avec Google',
                    style: TextStyle(color: _darkGreen, fontWeight: FontWeight.w600),
                  ),
                  onPressed: _loading ? null : _loginWithGoogle,
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}