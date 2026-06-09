import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _bg      = Color(0xFF0D1117);
const _card    = Color(0xFF161B22);
const _primary = Color(0xFF00C851);
const _border  = Color(0xFF30363D);
const _muted   = Color(0xFF8B949E);

class CreateEventScreen extends StatefulWidget {
  final String categoryId;
  final bool isCoinMode;
  final String coinName;
  const CreateEventScreen({
    super.key,
    required this.categoryId,
    this.isCoinMode = false,
    this.coinName = 'Ficha',
  });

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _titleCtrl   = TextEditingController();
  final _optionsCtrl = TextEditingController();
  int _points = 1;
  bool _loading = false;

  List<String> get _parsedOptions => _optionsCtrl.text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _optionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) { _snack('Coloque um título'); return; }
    final options = _parsedOptions;
    if (options.length < 2) { _snack('Adicione pelo menos 2 opções separadas por vírgula'); return; }

    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) { _snack('Sessão expirada.'); return; }

      final event = await client
          .from('events')
          .insert({
            'title': title,
            'created_by': userId,
            'category_id': widget.categoryId,
            'points': _points,
          })
          .select()
          .single();

      await client.from('options').insert(
          options.map((t) => {'event_id': event['id'], 'title': t}).toList());

      if (mounted) Navigator.of(context).pop(true);
    } catch (e, stack) {
      debugPrint('ERRO criar evento: $e\n$stack');
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: _card,
            title: const Text('Erro ao criar evento'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK', style: TextStyle(color: _primary)),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) {
    final options = _parsedOptions;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('Novo Evento'), backgroundColor: _bg),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // título
            TextField(
              controller: _titleCtrl,
              autofocus: true,
              decoration: _inputDec('Título do evento *',
                  hint: 'Ex: Quem bust out primeiro?'),
            ),
            const SizedBox(height: 24),

            // opções
            Text('Opções', style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15, color: _primary)),
            const SizedBox(height: 8),
            TextField(
              controller: _optionsCtrl,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: _inputDec('Separe por vírgula *',
                  hint: 'Ex: João, Pedro, Maria'),
            ),
            const SizedBox(height: 12),
            if (options.isNotEmpty) ...[
              Wrap(
                spacing: 8, runSpacing: 8,
                children: options.map((o) => Chip(
                  label: Text(o),
                  backgroundColor: _primary.withValues(alpha: 0.12),
                  side: const BorderSide(color: _primary),
                  labelStyle: const TextStyle(
                      color: _primary, fontWeight: FontWeight.w500),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                )).toList(),
              ),
              const SizedBox(height: 6),
              Text('${options.length} opção${options.length != 1 ? 'ões' : ''}',
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ] else
              const Text('As opções aparecerão aqui conforme você digita',
                  style: TextStyle(color: _muted, fontSize: 12)),

            const SizedBox(height: 28),

            // peso / multiplicador — só aparece no modo palpite
            if (!widget.isCoinMode) ...[
              Row(children: [
                const Text('Peso do evento',
                    style: TextStyle(fontWeight: FontWeight.bold,
                        fontSize: 15, color: _primary)),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Quem acertar ganha este número de pontos.\n'
                      'Use pesos maiores para eventos mais difíceis.',
                  child: const Icon(Icons.info_outline, size: 16, color: _muted),
                ),
              ]),
              const SizedBox(height: 4),
              const Text('Quanto vale acertar este evento?',
                  style: TextStyle(fontSize: 12, color: _muted)),
              const SizedBox(height: 12),
              _PointsSelector(
                value: _points,
                onChanged: (v) => setState(() => _points = v),
              ),
              const SizedBox(height: 32),
            ] else
              const SizedBox(height: 32),
            FilledButton(
              onPressed: _loading ? null : _create,
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Criar Evento',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
    filled: true,
    fillColor: _card,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primary)),
  );
}

// ── seletor de peso 1–10 ─────────────────────────────────────
class _PointsSelector extends StatelessWidget {
  final int value;
  final void Function(int) onChanged;

  const _PointsSelector({required this.value, required this.onChanged});

  static const _labels = {
    1: 'Fácil',
    2: 'Normal',
    3: 'Médio',
    5: 'Difícil',
    8: 'Muito difícil',
    10: 'Épico',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _labels.entries.map((e) {
        final selected = value == e.key;
        return GestureDetector(
          onTap: () => onChanged(e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? _primary.withValues(alpha: 0.12) : _card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? _primary : _border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${e.key}x',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900,
                      color: selected ? _primary : Colors.white)),
              Text(e.value,
                  style: TextStyle(
                      fontSize: 10,
                      color: selected ? _primary : _muted)),
            ]),
          ),
        );
      }).toList(),
    );
  }
}
