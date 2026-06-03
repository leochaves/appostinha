import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

class UpdatePasswordScreen extends StatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    final password = _passwordCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (password.length < 6) {
      _snack('A senha deve ter pelo menos 6 caracteres');
      return;
    }
    if (password != confirm) {
      _snack('As senhas não coincidem');
      return;
    }

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      // Remove o ?code= da URL para não contaminar sessões futuras
      if (kIsWeb) {
        web.window.history.replaceState(null, '', '/');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Senha atualizada com sucesso!'),
            backgroundColor: Color(0xFF00C851),
          ),
        );
        // _RootRouter ouve userUpdated e redireciona para HomeScreen
      }
    } on AuthException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_reset, size: 64, color: Color(0xFF00C851)),
              const SizedBox(height: 16),
              const Text(
                'Nova senha',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Escolha uma nova senha para sua conta',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: _inputDec('Nova senha'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmCtrl,
                obscureText: true,
                decoration: _inputDec('Confirmar senha'),
                onSubmitted: (_) => _update(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _update,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00C851),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Text('Salvar nova senha',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFF161B22),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00C851)),
        ),
      );
}
