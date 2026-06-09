import 'package:flutter/material.dart';
import '../utils/error_utils.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _bg = Color(0xFF0D1117);
const _card = Color(0xFF161B22);
const _primary = Color(0xFF00C851);
const _border = Color(0xFF30363D);
const _muted = Color(0xFF8B949E);

class CreateTournamentScreen extends StatefulWidget {
  const CreateTournamentScreen({super.key});

  @override
  State<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends State<CreateTournamentScreen> {
  final _nameCtrl      = TextEditingController();
  final _descCtrl      = TextEditingController();
  final _coinNameCtrl  = TextEditingController(text: 'Ficha');
  final _coinsCtrl     = TextEditingController(text: '500');

  String _mode = 'prediction'; // 'prediction' | 'coin'
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _coinNameCtrl.dispose();
    _coinsCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite o nome do torneio'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_mode == 'coin') {
      final coinName = _coinNameCtrl.text.trim();
      if (coinName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Digite o nome da moeda'), backgroundColor: Colors.red),
        );
        return;
      }
    }

    setState(() => _loading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sessão expirada. Faça login novamente.'), backgroundColor: Colors.red),
        );
        setState(() => _loading = false);
        return;
      }

      final initialCoins = int.tryParse(_coinsCtrl.text) ?? 500;

      await Supabase.instance.client.from('tournaments').insert({
        'name': name,
        'slug': _toSlug(name),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'created_by': userId,
        'mode': _mode,
        'coin_name': _coinNameCtrl.text.trim().isEmpty ? 'Ficha' : _coinNameCtrl.text.trim(),
        'initial_coins': initialCoins,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('ERRO [create_tournament_screen.dart]: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Novo Torneio'),
        backgroundColor: _bg,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Nome
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: _inputDec('Nome do torneio *'),
            ),
            const SizedBox(height: 16),

            // Descrição
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: _inputDec('Descrição / Premiação (opcional)'),
            ),
            const SizedBox(height: 28),

            // Modo
            const Text('Modo de pontuação',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _muted)),
            const SizedBox(height: 10),
            _ModeSelector(
              selected: _mode,
              onChanged: (v) => setState(() => _mode = v),
            ),
            const SizedBox(height: 20),

            // Configurações do modo moeda
            if (_mode == 'coin') ...[
              _SectionCard(
                children: [
                  const Text('Configurar moeda',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _primary)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _coinNameCtrl,
                    decoration: _inputDec('Nome da moeda *  (ex: Ficha, Crédito, Bolinha)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _coinsCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _inputDec('Saldo inicial por participante'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cada participante aprovado receberá este saldo para apostar.',
                    style: TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            FilledButton(
              onPressed: _loading ? null : _create,
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Criar torneio',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  String _toSlug(String name) {
    final accents = {
      'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ý': 'y', 'ç': 'c', 'ñ': 'n',
      'À': 'a', 'Á': 'a', 'Â': 'a', 'Ã': 'a', 'Ä': 'a',
      'È': 'e', 'É': 'e', 'Ê': 'e', 'Ë': 'e',
      'Ì': 'i', 'Í': 'i', 'Î': 'i', 'Ï': 'i',
      'Ò': 'o', 'Ó': 'o', 'Ô': 'o', 'Õ': 'o', 'Ö': 'o',
      'Ù': 'u', 'Ú': 'u', 'Û': 'u', 'Ü': 'u',
      'Ý': 'y', 'Ç': 'c', 'Ñ': 'n',
    };
    var s = name;
    accents.forEach((from, to) => s = s.replaceAll(from, to));
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
  }

  InputDecoration _inputDec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: _card,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary),
        ),
      );
}

class _ModeSelector extends StatelessWidget {
  final String selected;
  final void Function(String) onChanged;

  const _ModeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _ModeCard(
          value: 'prediction',
          selected: selected == 'prediction',
          icon: '🎯',
          title: 'Palpite',
          subtitle: 'Cada voto vale 1 palpite. Ranking por acertos.',
          onTap: () => onChanged('prediction'),
        )),
        const SizedBox(width: 12),
        Expanded(child: _ModeCard(
          value: 'coin',
          selected: selected == 'coin',
          icon: '🪙',
          title: 'Moeda',
          subtitle: 'Participantes apostam moedas. Ranking por lucro.',
          onTap: () => onChanged('coin'),
        )),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String value;
  final bool selected;
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.value,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? _primary.withValues(alpha: 0.08) : _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _primary : _border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: selected ? _primary : Colors.white)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(fontSize: 11, color: _muted, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
