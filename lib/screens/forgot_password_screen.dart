import 'package:flutter/material.dart';
import '../services/auth_service.dart';

const _darkGreen = Color(0xFF1B3A32);
const _terra     = Color(0xFFC4704F);

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email;
  bool _loading = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_email.text.trim().isEmpty || !_email.text.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renseigne un e-mail valide.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await AuthService.resetPassword(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _sent = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mot de passe oublié'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: _darkGreen),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _sent ? _buildConfirmation() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildConfirmation() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _darkGreen.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            size: 40,
            color: _darkGreen,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'E-mail envoyé',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _darkGreen,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Un lien de réinitialisation a été envoyé à\n${_email.text.trim()}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        const Text(
          'Vérifie ta boîte de réception (et tes spams).',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.black38),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _darkGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Retour à la connexion'),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mot de passe oublié ?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: _darkGreen,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Renseigne ton e-mail, on t\'enverra un lien pour choisir un nouveau mot de passe.',
          style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _send(),
          decoration: const InputDecoration(
            labelText: 'E-mail',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _darkGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _loading ? null : _send,
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
              'Envoyer le lien',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Retour',
              style: TextStyle(color: _terra, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}