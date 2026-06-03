import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateEventScreen extends StatefulWidget {
  final String categoryId;

  const CreateEventScreen({super.key, required this.categoryId});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _titleCtrl = TextEditingController();
  final _optionsCtrl = TextEditingController();
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
    if (title.isEmpty) {
      _snack('Coloque um título');
      return;
    }
    final options = _parsedOptions;
    if (options.length < 2) {
      _snack('Adicione pelo menos 2 opções separadas por vírgula');
      return;
    }

    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        _snack('Sessão expirada. Faça login novamente.');
        return;
      }

      final event = await client
          .from('events')
          .insert({
            'title': title,
            'created_by': userId,
            'category_id': widget.categoryId,
          })
          .select()
          .single();

      await client.from('options').insert(
            options.map((t) => {'event_id': event['id'], 'title': t}).toList(),
          );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e, stack) {
      debugPrint('ERRO criar evento: $e\n$stack');
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF161B22),
            title: const Text('Erro ao criar evento'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK', style: TextStyle(color: Color(0xFF00C851))),
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
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );

  @override
  Widget build(BuildContext context) {
    final options = _parsedOptions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Novo Evento'),
        backgroundColor: const Color(0xFF0D1117),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleCtrl,
              autofocus: true,
              decoration: _inputDec(
                'Título do evento *',
                hint: 'Ex: João vs Pedro, Quem ganha o campeonato?',
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Opções',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Color(0xFF00C851),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _optionsCtrl,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: _inputDec(
                'Separe por vírgula *',
                hint: 'Ex: João, Pedro, Maria',
              ),
            ),
            const SizedBox(height: 12),
            if (options.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: options
                    .map((o) => Chip(
                          label: Text(o),
                          backgroundColor: const Color(0xFF00C851).withValues(alpha: 0.12),
                          side: const BorderSide(color: Color(0xFF00C851), width: 1),
                          labelStyle: const TextStyle(
                            color: Color(0xFF00C851),
                            fontWeight: FontWeight.w500,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 6),
              Text(
                '${options.length} opção${options.length > 1 ? 'ões' : ''}',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ] else
              Text(
                'As opções aparecerão aqui conforme você digita',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _loading ? null : _create,
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
                  : const Text('Criar Evento',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
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
