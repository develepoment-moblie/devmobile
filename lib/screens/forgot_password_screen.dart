import 'package:flutter/material.dart';
import '../services/auth_service.dart';

const _cream = Color(0xFFF6F1EA);
const _darkGreen = Color(0xFF1B3A32);
const _muted = Color(0xFF8B8378);
const _dangerTxt = Color(0xFFB5423A);

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (_email.text.trim().isEmpty) {
      _snack('Renseigne ton email.');
      return;
    }

    setState(() => _loading = true);

    // Call the REST API method from AuthService
    final errorMessage = await AuthService.sendFirebaseResetEmail(_email.text);

    if (!mounted) return;
    setState(() => _loading = false);

    if (errorMessage == null) {
      _snack('Un email de réinitialisation a été envoyé !', isError: false);
      Navigator.pop(context);
    } else {
      _snack(errorMessage);
    }
  }

  void _snack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _dangerTxt : const Color(0xFF4A6B3E),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _cream,
        elevation: 0,
        foregroundColor: _darkGreen,
        title: const Text(
          'Mot de passe oublié',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
            const Text(
              'Réinitialisation par email',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _darkGreen,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Saisissez votre adresse email. Un lien sécurisé vous sera envoyé pour créer un nouveau mot de passe.',
              style: TextStyle(fontSize: 14, color: _muted),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail du compte',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _darkGreen,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _loading ? null : _sendResetEmail,
              child: _loading
                  ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
              )
                  : const Text('Envoyer le lien'),
            ),
          ],
        ),
      ),
    );
  }
}