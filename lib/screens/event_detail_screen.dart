import 'package:flutter/material.dart';
import '../utils/error_utils.dart';
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
  final bool isCoinMode;
  final String coinName;

  const EventDetailScreen({
    super.key,
    required this.event,
    this.isAdmin = false,
    this.breadcrumb,
    this.tournamentId,
    this.votingCode,
    this.isCoinMode = false,
    this.coinName = 'Ficha',
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late Event _event;
  bool _loading = false;
  String? _userPredictionOptionId; // modo palpite
  int _userCoins = 0;              // modo moeda — saldo atual
  Map<String, int> _userCoinBets = {}; // optionId → total apostado
  String? _memberStatus; // null = não membro / não logado, 'pending', 'approved', 'rejected'
  Map<String, List<String>> _voters = {}; // optionId → usernames

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    if (widget.isCoinMode) {
      _loadCoinData();
    } else {
      _loadUserPrediction();
    }
    if (widget.isAdmin || !widget.event.isOpen) _loadVoters();
  }

  Future<void> _reload() async {
    try {
      final data = await Supabase.instance.client
          .from('events')
          .select('*, options!options_event_id_fkey(*)')
          .eq('id', _event.id)
          .single();
      if (mounted) setState(() => _event = Event.fromJson(data));
      if (widget.isAdmin || !_event.isOpen) await _loadVoters();
    } catch (_) {}
  }

  Future<void> _loadVoters() async {
    try {
      final data = await Supabase.instance.client
          .from('bets')
          .select('option_id, profiles(username)')
          .eq('event_id', _event.id);
      final map = <String, List<String>>{};
      for (final row in data as List) {
        final optId = row['option_id'] as String;
        final username = (row['profiles'] as Map?)?['username'] as String? ?? '?';
        map.putIfAbsent(optId, () => []).add(username);
      }
      if (mounted) setState(() => _voters = map);
    } catch (e) {
      debugPrint('ERRO [_loadVoters]: $e');
    }
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

  Future<void> _loadCoinData() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (widget.tournamentId == null) return;

    if (userId == null) {
      if (mounted) setState(() => _memberStatus = null);
      return;
    }

    try {
      final memberData = await Supabase.instance.client
          .from('tournament_members')
          .select('coins, status')
          .eq('tournament_id', widget.tournamentId!)
          .eq('user_id', userId)
          .maybeSingle();

      final status = memberData?['status'] as String?;

      // só busca apostas se for membro aprovado
      final coinBets = <String, int>{};
      if (status == 'approved') {
        final betsData = await Supabase.instance.client
            .from('bets')
            .select('option_id, amount')
            .eq('event_id', _event.id)
            .eq('user_id', userId);
        for (final b in betsData as List) {
          final optId = b['option_id'] as String;
          final amt   = b['amount'] as int? ?? 0;
          coinBets[optId] = (coinBets[optId] ?? 0) + amt;
        }
      }

      if (mounted) {
        setState(() {
          _memberStatus = status; // null se não é membro
          _userCoins    = status == 'approved' ? (memberData?['coins'] as int? ?? 0) : 0;
          _userCoinBets = coinBets;
        });
      }
    } catch (_) {}
  }

  Future<void> _placeCoinBet(BetOption option, int amount) async {
    if (widget.tournamentId == null) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.rpc('place_coin_bet', params: {
        'p_tournament_id': widget.tournamentId!,
        'p_event_id':      _event.id,
        'p_option_id':     option.id,
        'p_amount':        amount,
      });
      await Future.wait([_reload(), _loadCoinData()]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$amount ${widget.coinName}${amount != 1 ? 's' : ''} apostados em "${option.title}"!'),
          backgroundColor: _primary,
        ));
      }
    } catch (e) {
      debugPrint('ERRO [event_detail_screen.dart]: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCoinBetSheet(BetOption option) {
    final ctrl = TextEditingController();
    // totalPool atual para cálculo das odds (será updated conforme usuário digita)
    final currentTotalPool = _event.options.fold(0, (s, o) => s + o.coinPool);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Apostar em "${option.title}"',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Saldo: $_userCoins ${widget.coinName}s',
                  style: const TextStyle(fontSize: 12, color: _muted)),
              const SizedBox(height: 16),
              // atalhos rápidos
              Wrap(
                spacing: 8, runSpacing: 8,
                children: [10, 25, 50, 100].where((v) => v <= _userCoins).map((v) =>
                  GestureDetector(
                    onTap: () {
                      ctrl.text = v.toString();
                      setSheet(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _primary.withValues(alpha: 0.3)),
                      ),
                      child: Text('$v', style: const TextStyle(
                          color: _primary, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                onChanged: (_) => setSheet(() {}),
                decoration: InputDecoration(
                  labelText: 'Quantidade de ${widget.coinName}s *',
                  filled: true,
                  fillColor: _bg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _primary)),
                ),
              ),
              // retorno estimado dinâmico
              Builder(builder: (_) {
                final amount = int.tryParse(ctrl.text.trim()) ?? 0;
                if (amount <= 0) return const SizedBox(height: 8);
                final newPool    = currentTotalPool + amount;
                final newOptPool = option.coinPool + amount;
                final estimated  = (amount * newPool / newOptPool).round();
                final profit     = estimated - amount;
                return Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _primary.withValues(alpha: 0.25)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.trending_up, color: _primary, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Se ganhar: ~$estimated ${widget.coinName}s  (${profit >= 0 ? '+' : ''}$profit lucro)',
                          style: const TextStyle(color: _primary, fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ]),
                  ),
                );
              }),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  final amount = int.tryParse(ctrl.text.trim());
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Digite um valor válido'),
                            backgroundColor: Colors.red));
                    return;
                  }
                  if (amount > _userCoins) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Saldo insuficiente ($_userCoins ${widget.coinName}s)'),
                            backgroundColor: Colors.red));
                    return;
                  }
                  Navigator.pop(ctx);
                  _placeCoinBet(option, amount);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: _primary, foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Confirmar aposta',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleClose() async {
    final newStatus = _event.status == 'open' ? 'closed' : 'open';
    setState(() => _loading = true);
    try {
      await Supabase.instance.client
          .from('events')
          .update({'status': newStatus})
          .eq('id', _event.id);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newStatus == 'closed'
              ? '🔒 Apostas encerradas!'
              : '🔓 Apostas reabertas!'),
          backgroundColor: newStatus == 'closed' ? _gold : _primary,
        ));
      }
    } catch (e) {
      debugPrint('ERRO [event_detail_screen.dart]: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      debugPrint('ERRO [event_detail_screen.dart]: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
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
      debugPrint('ERRO [event_detail_screen.dart]: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(friendlyError(e)),
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
      debugPrint('ERRO [event_detail_screen.dart]: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
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
      debugPrint('ERRO [event_detail_screen.dart]: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCoin     = widget.isCoinMode;
    final total      = _event.totalPredictions;
    final totalPool  = _event.options.fold(0, (s, o) => s + o.coinPool);
    final opts       = [..._event.options]
      ..sort((a, b) => isCoin
          ? b.coinPool.compareTo(a.coinPool)
          : b.predictionCount.compareTo(a.predictionCount));
    final isResolved = _event.status == 'resolved';
    final isOpen     = _event.isOpen;
    final alreadyBet = _userPredictionOptionId != null; // só palpite
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
                            isCoinMode: isCoin,
                            coinName: widget.coinName,
                            totalPool: totalPool,
                            userCoins: _userCoins,
                            showUserBalance: isCoin && _memberStatus == 'approved',
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
                            final isLead    = i == 0;
                            final isWinner  = _event.winningOptionId == o.id;
                            final isSelected = isCoin
                                ? _userCoinBets.containsKey(o.id)
                                : _userPredictionOptionId == o.id;
                            final pct = isCoin
                                ? (totalPool > 0 ? o.coinPool / totalPool : 0.0)
                                : (total > 0 ? o.predictionCount / total : 0.0);
                            final canTapCoin = isCoin &&
                                isOpen &&
                                _memberStatus == 'approved' &&
                                _userCoins > 0;
                            return _OptionCard(
                              option: o,
                              index: i,
                              pct: pct,
                              total: isCoin ? totalPool : total,
                              isLead: isLead,
                              isWinner: isWinner,
                              isSelected: isSelected,
                              canTap: isOpen && (isCoin ? canTapCoin : !alreadyBet),
                              isCoinMode: isCoin,
                              coinName: widget.coinName,
                              userBetAmount: _userCoinBets[o.id],
                              onTap: () => isCoin
                                  ? _showCoinBetSheet(o)
                                  : _makePrediction(o),
                            );
                          }),

                          // Hint / status de participação
                          if (isOpen) _ParticipationHint(
                            isCoinMode: isCoin,
                            coinName: widget.coinName,
                            memberStatus: _memberStatus,
                            userCoins: _userCoins,
                            alreadyBet: alreadyBet,
                            isLoggedIn: Supabase.instance.client.auth.currentUser != null,
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

                          // Seção de votos
                          if ((widget.isAdmin || !isOpen) && _voters.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _VotersSection(
                              options: opts,
                              voters: _voters,
                              isAdmin: widget.isAdmin,
                              isOpen: isOpen,
                            ),
                          ],

                          // Seção admin — fechar apostas / resolver
                          if (widget.isAdmin && !isResolved) ...[
                            const SizedBox(height: 24),
                            _AdminResolveSection(
                              options: opts,
                              loading: _loading,
                              isOpen: isOpen,
                              onClose: _toggleClose,
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
  final bool isCoinMode;
  final String coinName;
  final int totalPool;
  final int userCoins;
  final bool showUserBalance;

  const _HeroCard({
    required this.breadcrumb,
    required this.title,
    required this.total,
    required this.status,
    this.isCoinMode = false,
    this.coinName = 'Ficha',
    this.totalPool = 0,
    this.userCoins = 0,
    this.showUserBalance = false,
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
          if (isCoinMode) ...[
            Text('Pool: $totalPool ${coinName}s no total',
                style: const TextStyle(color: _muted, fontSize: 12)),
            if (showUserBalance) ...[
              const SizedBox(height: 2),
              Text('Seu saldo: $userCoins ${coinName}s',
                  style: const TextStyle(color: _primary, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ] else
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
  final bool isCoinMode;
  final String coinName;
  final int? userBetAmount;
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
    this.isCoinMode = false,
    this.coinName = 'Ficha',
    this.userBetAmount,
  });

  @override
  Widget build(BuildContext context) {
    final pctLabel = total > 0 ? '${(pct * 100).round()}%' : null;
    final poolLabel = isCoinMode ? '${option.coinPool} $coinName${option.coinPool != 1 ? 's' : ''}' : null;

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
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (isCoinMode) ...[
                    // odd dinâmica: total_pool / option.coinPool
                    Builder(builder: (_) {
                      final hasPool = option.coinPool > 0 && total > 0;
                      final odd = hasPool ? total / option.coinPool : 0.0;
                      final oddStr = hasPool
                          ? (odd == odd.truncateToDouble()
                              ? '${odd.toInt()}x'
                              : '${odd.toStringAsFixed(2)}x')
                          : '—';
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isWinner ? _gold : _primary).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(oddStr,
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w900,
                                    color: isWinner ? _gold : _primary)),
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 2),
                    Text(poolLabel ?? '0 ${coinName}s',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            color: isWinner ? _gold : isLead ? _primary : _muted)),
                    if (pctLabel != null)
                      Text(pctLabel, style: const TextStyle(fontSize: 10, color: _muted)),
                    if (userBetAmount != null && userBetAmount! > 0)
                      Text('seu: $userBetAmount',
                          style: const TextStyle(fontSize: 10, color: _primary,
                              fontWeight: FontWeight.bold)),
                  ] else if (pctLabel != null)
                    Text(pctLabel,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                            color: isWinner ? _gold : isLead ? _primary : _muted))
                  else if (canTap)
                    const Icon(Icons.chevron_right, color: _muted, size: 18),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ParticipationHint extends StatelessWidget {
  final bool isCoinMode;
  final String coinName;
  final String? memberStatus;
  final int userCoins;
  final bool alreadyBet;
  final bool isLoggedIn;

  const _ParticipationHint({
    required this.isCoinMode,
    required this.coinName,
    required this.memberStatus,
    required this.userCoins,
    required this.alreadyBet,
    required this.isLoggedIn,
  });

  @override
  Widget build(BuildContext context) {
    if (!isCoinMode) {
      // modo palpite: mensagem simples
      if (alreadyBet) return const SizedBox.shrink();
      return const Padding(
        padding: EdgeInsets.only(top: 4, bottom: 8),
        child: Text('Toque em uma opção para registrar seu palpite.',
            style: TextStyle(color: _muted, fontSize: 12)),
      );
    }

    // modo moeda
    String icon;
    String msg;
    Color color;

    if (!isLoggedIn) {
      icon = '🔒'; msg = 'Faça login para participar.'; color = _muted;
    } else if (memberStatus == null) {
      icon = '🚪'; msg = 'Você não é participante deste torneio. Volte e clique em "Entrar".'; color = _gold;
    } else if (memberStatus == 'pending') {
      icon = '⏳'; msg = 'Aguardando aprovação do admin para participar.'; color = _gold;
    } else if (memberStatus == 'rejected') {
      icon = '🚫'; msg = 'Sua entrada neste torneio foi recusada.'; color = Colors.red;
    } else if (userCoins <= 0) {
      icon = '💸'; msg = 'Sem $coinName${coinName.endsWith('s') ? '' : 's'} disponíveis. Peça ao admin.'; color = _muted;
    } else {
      // aprovado com saldo: mostra saldo e instrução
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text('Saldo: $userCoins $coinName${userCoins != 1 ? 's' : ''} · Toque para apostar',
            style: const TextStyle(color: _muted, fontSize: 12)),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Text(msg,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500))),
        ]),
      ),
    );
  }
}

class _VotersSection extends StatelessWidget {
  final List<BetOption> options;
  final Map<String, List<String>> voters;
  final bool isAdmin;
  final bool isOpen;

  const _VotersSection({
    required this.options,
    required this.voters,
    required this.isAdmin,
    required this.isOpen,
  });

  @override
  Widget build(BuildContext context) {
    final totalVotes = voters.values.fold(0, (s, v) => s + v.length);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('VOTOS',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                    letterSpacing: 1.5, color: _muted)),
            const SizedBox(width: 8),
            Text('$totalVotes no total',
                style: const TextStyle(fontSize: 10, color: _muted)),
            if (isAdmin && isOpen) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('só admin', style: TextStyle(
                    fontSize: 9, color: _gold, fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          ...options.map((o) {
            final names = voters[o.id] ?? [];
            if (names.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(o.title,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                    Text('${names.length}',
                        style: const TextStyle(
                            fontSize: 12, color: _primary,
                            fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: names.map((name) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _border),
                      ),
                      child: Text(name,
                          style: const TextStyle(fontSize: 11, color: Colors.white70)),
                    )).toList(),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AdminResolveSection extends StatelessWidget {
  final List<BetOption> options;
  final bool loading;
  final bool isOpen;
  final VoidCallback onClose;
  final void Function(BetOption) onResolve;

  const _AdminResolveSection({
    required this.options,
    required this.loading,
    required this.isOpen,
    required this.onClose,
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
          // cabeçalho ADMIN
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('ADMIN',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                      color: _gold, letterSpacing: 1)),
            ),
            const SizedBox(width: 10),
            Text(isOpen ? 'Controle do Evento' : 'Apostas Encerradas',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),

          // botão fechar / reabrir apostas
          GestureDetector(
            onTap: loading ? null : onClose,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isOpen
                    ? Colors.orange.withValues(alpha: 0.1)
                    : _primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isOpen
                      ? Colors.orange.withValues(alpha: 0.5)
                      : _primary.withValues(alpha: 0.5),
                ),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(
                  isOpen ? Icons.lock_outline : Icons.lock_open_outlined,
                  size: 16,
                  color: isOpen ? Colors.orange : _primary,
                ),
                const SizedBox(width: 8),
                Text(
                  isOpen ? 'Fechar apostas' : 'Reabrir apostas',
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold,
                    color: isOpen ? Colors.orange : _primary,
                  ),
                ),
              ]),
            ),
          ),

          // botões de resolver (só aparecem com apostas fechadas)
          if (!isOpen) ...[
            const SizedBox(height: 16),
            const Text(
              'Selecione o vencedor para encerrar e distribuir pontos/moedas:',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: options.map((o) => GestureDetector(
                onTap: loading ? null : () => onResolve(o),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: _gold.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '🏆 ${o.title.toUpperCase()} VENCEU',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                        color: _gold, letterSpacing: 0.5),
                  ),
                ),
              )).toList(),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              'Feche as apostas antes de declarar o vencedor.',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
