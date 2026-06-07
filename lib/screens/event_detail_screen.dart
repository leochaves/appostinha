import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/event.dart';
import '../widgets/app_logo.dart';
import '../models/bet_option.dart';
import '../services/vote_session.dart';

const _bg = Color(0xFF0D1117);
const _card = Color(0xFF161B22);
const _primary = Color(0xFF00C851);
const _gold = Color(0xFFD4A017);
const _border = Color(0xFF30363D);
const _muted = Color(0xFF8B949E);

class EventDetailScreen extends StatefulWidget {
  final Event event;
  final bool isAdmin;
  final String? breadcrumb;
  final String? tournamentId;
  final String? votingCode;

  const EventDetailScreen({
    super.key,
    required this.event,
    this.isAdmin = false,
    this.breadcrumb,
    this.tournamentId,
    this.votingCode,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late Event _event;
  bool _loading = false;
  String? _userPredictionOptionId;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _loadUserPrediction();
  }

  Future<void> _reload() async {
    try {
      final data = await Supabase.instance.client
          .from('events')
          .select('*, options!options_event_id_fkey(*)')
          .eq('id', _event.id)
          .single();
      if (mounted) setState(() => _event = Event.fromJson(data));
    } catch (_) {}
  }

  Future<void> _loadUserPrediction() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final data = await Supabase.instance.client
          .from('bets')
          .select('option_id')
          .eq('event_id', _event.id)
          .eq('user_id', userId)
          .maybeSingle();
      if (mounted && data != null) {
        setState(() => _userPredictionOptionId = data['option_id'] as String);
      }
    } catch (_) {}
  }

  Future<void> _resolveEvent(String winningOptionId) async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.rpc('resolve_event', params: {
        'p_event_id': _event.id,
        'p_winning_option_id': winningOptionId,
      });
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Evento resolvido! Badges entregues.'),
          backgroundColor: _primary,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _confirmResolve(BetOption option) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmar vencedor'),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.white, fontSize: 15),
            children: [
              const TextSpan(text: 'Marcar '),
              TextSpan(
                  text: '"${option.title}"',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: _gold)),
              const TextSpan(text: ' como vencedor?'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: _muted)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _resolveEvent(option.id);
            },
            style: FilledButton.styleFrom(
                backgroundColor: _gold, foregroundColor: Colors.black),
            child: const Text('Confirmar',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openEdit() {
    final titleCtrl = TextEditingController(text: _event.title);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Editar evento',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Título',
                filled: true,
                fillColor: _bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final newTitle = titleCtrl.text.trim();
                if (newTitle.isEmpty) return;
                Navigator.pop(context);
                setState(() => _loading = true);
                try {
                  await Supabase.instance.client
                      .from('events')
                      .update({'title': newTitle}).eq('id', _event.id);
                  await _reload();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Erro: $e'),
                        backgroundColor: Colors.red));
                  }
                } finally {
                  if (mounted) setState(() => _loading = false);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Salvar',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Deletar evento'),
        content: const Text(
            'Todos os palpites serão apagados. Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: _muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteEvent();
            },
            child: const Text('Deletar',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEvent() async {
    setState(() => _loading = true);
    try {
      final deleted = await Supabase.instance.client
          .from('events')
          .delete()
          .eq('id', _event.id)
          .select();
      if (deleted.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sem permissão ou evento não encontrado'),
          backgroundColor: Colors.orange,
        ));
        setState(() => _loading = false);
        return;
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
        setState(() => _loading = false);
      }
    }
  }

  Future<bool?> _showLoginPrompt() {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Entre para votar'),
        content: const Text(
            'Você precisa criar uma conta ou fazer login para registrar seu palpite.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: _muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: _primary, foregroundColor: Colors.black),
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showCodeDialog(String correctCode, String tournamentId) async {
    final ctrl = TextEditingController();
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: _card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Text('🔒 ', style: TextStyle(fontSize: 20)),
            Text('Código de votação'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Este torneio requer um código para votar.\nPeça o código ao organizador.',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'Digite o código',
                  errorText: error,
                  filled: true,
                  fillColor: _bg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _primary),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: _muted)),
            ),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().toUpperCase() ==
                    correctCode.toUpperCase()) {
                  Navigator.pop(ctx, true);
                } else {
                  setLocal(() => error = 'Código incorreto');
                }
              },
              style: FilledButton.styleFrom(
                  backgroundColor: _primary, foregroundColor: Colors.black),
              child: const Text('Validar',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      VoteSession.instance.validate(tournamentId);
      return true;
    }
    return false;
  }

  Future<void> _makePrediction(BetOption option) async {
    if (_userPredictionOptionId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Você já fez sua previsão neste evento')));
      return;
    }

    // 1. Verificar se está logado
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      final goLogin = await _showLoginPrompt();
      if (goLogin == true && mounted) {
        final currentPath = '/evento/${_event.id}';
        context.push('/auth?redirect=${Uri.encodeComponent(currentPath)}');
      }
      return;
    }

    // 2. Verificar código de votação
    final code = widget.votingCode;
    final tournamentId = widget.tournamentId;
    if (code != null && code.isNotEmpty && tournamentId != null) {
      final already = VoteSession.instance.isValidated(tournamentId);
      if (!already) {
        final ok = await _showCodeDialog(code, tournamentId);
        if (!ok) return;
      }
    }

    // 3. Confirmar palpite
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmar palpite'),
        content: Text('Apostar em "${option.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: _muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: _primary, foregroundColor: Colors.black),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client.rpc('make_prediction', params: {
        'p_user_id': userId,
        'p_event_id': _event.id,
        'p_option_id': option.id,
      });
      setState(() => _userPredictionOptionId = option.id);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Palpite feito: "${option.title}"!'),
          backgroundColor: _primary,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _event.totalPredictions;
    final opts = [..._event.options]
      ..sort((a, b) => b.predictionCount.compareTo(a.predictionCount));
    final isResolved = _event.status == 'resolved';
    final isOpen = _event.isOpen;
    final alreadyBet = _userPredictionOptionId != null;
    final breadcrumb = widget.breadcrumb ?? '';

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // AppBar
            _EventAppBar(
              breadcrumb: breadcrumb,
              title: _event.title,
              isAdmin: widget.isAdmin,
              loading: _loading,
              onBack: () => context.canPop() ? context.pop() : context.go('/'),
              onEdit: _openEdit,
              onDelete: _confirmDelete,
            ),
            Expanded(
              child: _loading && _event.options.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Hero card
                          _HeroCard(
                            breadcrumb: breadcrumb,
                            title: _event.title,
                            total: total,
                            status: _event.status,
                          ),
                          const SizedBox(height: 24),

                          // Seção de previsão
                          if (!isResolved) ...[
                            const _SectionLabel(label: 'Sua Previsão'),
                            const SizedBox(height: 10),
                          ] else ...[
                            const _SectionLabel(label: 'Resultado'),
                            const SizedBox(height: 10),
                          ],

                          // Opções
                          ...opts.asMap().entries.map((entry) {
                            final i = entry.key;
                            final o = entry.value;
                            final isLead = i == 0;
                            final isWinner = _event.winningOptionId == o.id;
                            final isSelected = _userPredictionOptionId == o.id;
                            final pct = total > 0
                                ? o.predictionCount / total
                                : 0.0;
                            return _OptionCard(
                              option: o,
                              index: i,
                              pct: pct,
                              total: total,
                              isLead: isLead,
                              isWinner: isWinner,
                              isSelected: isSelected,
                              canTap: isOpen && !alreadyBet,
                              onTap: () => _makePrediction(o),
                            );
                          }),

                          // Hint para usuário
                          if (isOpen && !alreadyBet)
                            const Padding(
                              padding: EdgeInsets.only(top: 4, bottom: 8),
                              child: Text(
                                'Toque em uma opção para registrar sua previsão.',
                                style: TextStyle(color: _muted, fontSize: 12),
                              ),
                            ),

                          // Banner resolvido
                          if (isResolved) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _gold.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: _gold.withValues(alpha: 0.3)),
                              ),
                              child: const Row(children: [
                                Icon(Icons.emoji_events,
                                    color: _gold, size: 18),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Evento encerrado. Badges distribuídos!',
                                    style: TextStyle(
                                        color: _gold,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ]),
                            ),
                          ],

                          // Seção admin — resolver partida
                          if (widget.isAdmin && isOpen) ...[
                            const SizedBox(height: 24),
                            _AdminResolveSection(
                              options: opts,
                              loading: _loading,
                              onResolve: _confirmResolve,
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets ──────────────────────────────────────────────────

class _EventAppBar extends StatelessWidget {
  final String breadcrumb;
  final String title;
  final bool isAdmin;
  final bool loading;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EventAppBar({
    required this.breadcrumb,
    required this.title,
    required this.isAdmin,
    required this.loading,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(bottom: BorderSide(color: _border, width: 0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.chevron_left, color: _muted, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          const AppBarBrand(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (breadcrumb.isNotEmpty)
                  Text(breadcrumb.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: _muted),
                      overflow: TextOverflow.ellipsis),
                Text(title,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (isAdmin) ...[
            GestureDetector(
              onTap: loading ? null : onEdit,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.edit_outlined, color: _muted, size: 16),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: loading ? null : onDelete,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(18)),
                child:
                    const Icon(Icons.delete_outline, color: Colors.red, size: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String breadcrumb;
  final String title;
  final int total;
  final String status;

  const _HeroCard({
    required this.breadcrumb,
    required this.title,
    required this.total,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'open':
        statusColor = _primary;
        statusLabel = 'Aberto';
      case 'resolved':
        statusColor = _gold;
        statusLabel = 'Resolvido';
      default:
        statusColor = _muted;
        statusLabel = 'Fechado';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == 'resolved'
              ? _gold.withValues(alpha: 0.3)
              : _primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (breadcrumb.isNotEmpty)
                Expanded(
                  child: Text(
                    breadcrumb.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: _primary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                height: 1.2,
                letterSpacing: -0.5),
          ),
          const SizedBox(height: 12),
          Text('$total palpites no total',
              style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: _muted),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final BetOption option;
  final int index;
  final double pct;
  final int total;
  final bool isLead;
  final bool isWinner;
  final bool isSelected;
  final bool canTap;
  final VoidCallback onTap;

  const _OptionCard({
    required this.option,
    required this.index,
    required this.pct,
    required this.total,
    required this.isLead,
    required this.isWinner,
    required this.isSelected,
    required this.canTap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pctLabel = total > 0 ? '${(pct * 100).round()}%' : null;

    Color borderColor;
    Color fillColor;
    Color nameColor;
    if (isWinner) {
      borderColor = _gold.withValues(alpha: 0.6);
      fillColor = _gold.withValues(alpha: 0.18);
      nameColor = _gold;
    } else if (isSelected) {
      borderColor = _primary.withValues(alpha: 0.7);
      fillColor = _primary.withValues(alpha: 0.15);
      nameColor = _primary;
    } else if (isLead && total > 0) {
      borderColor = _border;
      fillColor = _primary.withValues(alpha: 0.12);
      nameColor = Colors.white;
    } else {
      borderColor = _border;
      fillColor = Colors.transparent;
      nameColor = Colors.white;
    }

    return GestureDetector(
      onTap: canTap ? onTap : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: isSelected || isWinner ? 1.5 : 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(children: [
            // fill bar de fundo
            if (pct > 0)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: pct.clamp(0.0, 1.0),
                  child: Container(color: fillColor),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Expanded(
                  child: Row(children: [
                    if (isWinner)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.emoji_events, color: _gold, size: 16),
                      )
                    else if (isSelected)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.check_circle, color: _primary, size: 16),
                      )
                    else if (canTap)
                      Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _border),
                        ),
                      ),
                    Expanded(
                      child: Text(option.title,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: nameColor)),
                    ),
                  ]),
                ),
                if (pctLabel != null)
                  Text(pctLabel,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: isWinner ? _gold : isLead ? _primary : _muted))
                else if (canTap)
                  const Icon(Icons.chevron_right, color: _muted, size: 18),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _AdminResolveSection extends StatelessWidget {
  final List<BetOption> options;
  final bool loading;
  final void Function(BetOption) onResolve;

  const _AdminResolveSection({
    required this.options,
    required this.loading,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('ADMIN',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: _gold,
                        letterSpacing: 1)),
              ),
              const SizedBox(width: 10),
              const Text('Resolver Partida',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Selecione o vencedor para encerrar a partida e distribuir os pontos.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: options.map((o) => GestureDetector(
              onTap: loading ? null : () => onResolve(o),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: _gold.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${o.title.toUpperCase()} VENCEU',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: _gold,
                      letterSpacing: 0.5),
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}
