import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/nova_logo.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remplis e-mail et mot de passe.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      if (_isRegister) {
        await AuthService.register(
          _email.text.trim(),
          _pass.text,
          _name.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Compte créé. Connexion...')),
          );
        }
      } else {
        await AuthService.login(_email.text.trim(), _pass.text);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🖼️ Logo réutilisable
              const NovaLogo(size: 120, circular: false),
              const SizedBox(height: 16),
              const Text(
                'NOVA PARIS',
                style: TextStyle(
                  fontSize: 22,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),
              if (_isRegister) ...[
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nom complet'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mot de passe'),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Text(_isRegister ? 'Créer un compte' : 'Se connecter'),
                ),
              ),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => setState(() => _isRegister = !_isRegister),
                child: Text(
                  _isRegister ? "J'ai déjà un compte" : 'Créer un compte',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}