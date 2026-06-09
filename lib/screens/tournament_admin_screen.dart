import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tournament.dart';
import '../models/tournament_admin.dart';
import '../utils/error_utils.dart';

const _bg    = Color(0xFF0D1117);
const _card  = Color(0xFF161B22);
const _primary = Color(0xFF00C851);
const _gold  = Color(0xFFD4A017);
const _border = Color(0xFF30363D);
const _muted = Color(0xFF8B949E);
const _red   = Colors.red;

// ── modelo local de membro ──────────────────────────────────
class _Member {
  final String userId;
  final String username;
  final String status;
  final int coins;
  final int initialCoins;
  final int bonusCoins;
  final DateTime joinedAt;

  _Member({
    required this.userId,
    required this.username,
    required this.status,
    required this.coins,
    required this.initialCoins,
    required this.bonusCoins,
    required this.joinedAt,
  });

  int get profit => coins - initialCoins - bonusCoins;
}

// ════════════════════════════════════════════════════════════
class TournamentAdminScreen extends StatefulWidget {
  final Tournament tournament;
  final VoidCallback? onChanged;

  const TournamentAdminScreen({
    super.key,
    required this.tournament,
    this.onChanged,
  });

  @override
  State<TournamentAdminScreen> createState() => _TournamentAdminScreenState();
}

class _TournamentAdminScreenState extends State<TournamentAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  // dados
  List<_Member> _pending  = [];
  List<_Member> _approved = [];
  List<TournamentAdmin> _admins = [];
  bool _loading = true;
  final _currentUserId = Supabase.instance.client.auth.currentUser?.id;

  bool get _isOwner => _admins.any((a) => a.userId == _currentUserId && a.isOwner);

  late Tournament _t; // torneio local (pode ser editado)

  @override
  void initState() {
    super.initState();
    _t = widget.tournament;
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        Supabase.instance.client
            .from('tournament_members')
            .select('*, profiles!tournament_members_user_id_fkey(username)')
            .eq('tournament_id', _t.id)
            .order('joined_at', ascending: true),
        Supabase.instance.client
            .from('tournament_admins')
            .select('*, profiles!tournament_admins_user_id_fkey(username)')
            .eq('tournament_id', _t.id)
            .order('added_at', ascending: true),
      ]);

      final members = (results[0] as List).map((m) => _Member(
        userId:       m['user_id'] as String,
        username:     (m['profiles'] as Map)['username'] as String? ?? 'Usuário',
        status:       m['status'] as String,
        coins:        m['coins'] as int? ?? 0,
        initialCoins: m['initial_coins'] as int? ?? 0,
        bonusCoins:   m['bonus_coins'] as int? ?? 0,
        joinedAt:     DateTime.parse(m['joined_at'] as String),
      )).toList();

      final admins = (results[1] as List)
          .map((a) => TournamentAdmin.fromJson(a))
          .toList();

      if (mounted) {
        setState(() {
          _pending  = members.where((m) => m.status == 'pending').toList();
          _approved = members.where((m) => m.status == 'approved').toList();
          _admins   = admins;
          _loading  = false;
        });
      }
    } catch (e) {
      debugPrint('ERRO admin panel: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── aprovação ──────────────────────────────────────────────
  Future<void> _approve(String userId) async {
    try {
      await Supabase.instance.client.rpc('approve_member', params: {
        'p_tournament_id': _t.id,
        'p_user_id': userId,
      });
      _load();
      _snack('Participante aprovado ✓', _primary);
    } catch (e) { _snack('Erro: $e', _red); }
  }

  Future<void> _reject(String userId) async {
    try {
      await Supabase.instance.client.rpc('reject_member', params: {
        'p_tournament_id': _t.id,
        'p_user_id': userId,
      });
      _load();
      _snack('Participante rejeitado', Colors.orange);
    } catch (e) { _snack('Erro: $e', _red); }
  }

  // ── moedas ─────────────────────────────────────────────────
  void _showAddCoins(_Member member) {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    bool affectsRanking = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                _Avatar(username: member.username, color: _primary),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.username,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    Text('Saldo: ${member.coins} ${_t.coinName}s',
                        style: const TextStyle(fontSize: 12, color: _muted)),
                  ],
                )),
              ]),
              const SizedBox(height: 20),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
                decoration: _inputDec('Valor (negativo para débito)'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: _inputDec('Motivo (opcional)'),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setLocal(() => affectsRanking = !affectsRanking),
                child: Row(children: [
                  Checkbox(
                    value: affectsRanking,
                    onChanged: (v) => setLocal(() => affectsRanking = v ?? false),
                    activeColor: _primary,
                  ),
                  const Expanded(
                    child: Text(
                      'Conta no ranking (lucro)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ]),
              ),
              const Text(
                'Se desmarcado, o valor não afeta a posição no ranking.',
                style: TextStyle(fontSize: 11, color: _muted),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  final amount = int.tryParse(amountCtrl.text);
                  if (amount == null || amount == 0) {
                    _snack('Digite um valor válido', _red);
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    await Supabase.instance.client.rpc('add_coins', params: {
                      'p_tournament_id':   _t.id,
                      'p_user_id':         member.userId,
                      'p_amount':          amount,
                      'p_reason':          reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
                      'p_affects_ranking': affectsRanking,
                    });
                    _load();
                    _snack(
                      '${amount > 0 ? '+' : ''}$amount ${_t.coinName}s para ${member.username}',
                      amount > 0 ? _primary : Colors.orange,
                    );
                  } catch (e) { _snack('Erro: $e', _red); }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── admins ─────────────────────────────────────────────────
  final _emailCtrl = TextEditingController();
  bool _addingAdmin = false;

  Future<void> _addAdmin() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() => _addingAdmin = true);
    try {
      final username = await Supabase.instance.client.rpc(
        'add_tournament_admin',
        params: {'p_tournament_id': _t.id, 'p_email': email},
      ) as String;
      _emailCtrl.clear();
      await _load();
      _snack('$username adicionado como admin!', _primary);
    } catch (e) {
      debugPrint('ERRO [tournament_admin_screen.dart]: $e');
      _snack('Erro: $e', _red);
    } finally {
      if (mounted) setState(() => _addingAdmin = false);
    }
  }

  Future<void> _removeAdmin(TournamentAdmin admin) async {
    try {
      await Supabase.instance.client
          .from('tournament_admins')
          .delete()
          .eq('tournament_id', _t.id)
          .eq('user_id', admin.userId);
      await _load();
      _snack('${admin.username} removido', Colors.orange);
    } catch (e) { _snack('Erro: $e', _red); }
  }

  // ── configurações ──────────────────────────────────────────
  void _editDescription() {
    final ctrl = TextEditingController(text: _t.description ?? '');
    _bottomSheet('Descrição / Premiação', [
      TextField(controller: ctrl, maxLines: 5, autofocus: true,
          decoration: _inputDec('Descreva regras e premiação')),
      const SizedBox(height: 16),
      _saveBtn(() async {
        Navigator.pop(context);
        await Supabase.instance.client.from('tournaments')
            .update({'description': ctrl.text.trim().isEmpty ? null : ctrl.text.trim()})
            .eq('id', _t.id);
        _load();
        widget.onChanged?.call();
      }),
    ]);
  }

  void _editVotingCode() {
    final ctrl = TextEditingController(text: _t.votingCode ?? '');
    _bottomSheet('Código de acesso', [
      TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: _inputDec('Deixe vazio para votação livre'),
      ),
      const SizedBox(height: 8),
      const Text('Participantes precisam inserir este código para entrar.',
          style: TextStyle(fontSize: 11, color: _muted)),
      const SizedBox(height: 16),
      _saveBtn(() async {
        final code = ctrl.text.trim().toUpperCase();
        Navigator.pop(context);
        await Supabase.instance.client.from('tournaments')
            .update({'voting_code': code.isEmpty ? null : code})
            .eq('id', _t.id);
        _load();
        widget.onChanged?.call();
        _snack(code.isEmpty ? 'Código removido' : 'Código: $code', _primary);
      }),
    ]);
  }

  void _awardChampions() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Premiar Campeões'),
        content: const Text(
            'Distribui os badges 🥇🥈🥉 para o top 3 do leaderboard atual.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: _muted))),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final result = await Supabase.instance.client.rpc(
                  'award_tournament_champions',
                  params: {'p_tournament_id': _t.id},
                );
                _snack('${(result as List).length} campeão(ões) premiado(s)! 🏆', _gold);
              } catch (e) { _snack('Erro: $e', _red); }
            },
            style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.black),
            child: const Text('Premiar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── helpers ────────────────────────────────────────────────
  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color));
  }

  void _bottomSheet(String title, List<Widget> children) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _saveBtn(VoidCallback onTap) => FilledButton(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      backgroundColor: _primary,
      foregroundColor: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    child: const Text('Salvar', style: TextStyle(fontWeight: FontWeight.bold)),
  );

  InputDecoration _inputDec(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: _bg,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primary)),
  );

  // ════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Painel do Admin',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(_t.name, style: const TextStyle(fontSize: 12, color: _muted)),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: _primary,
          labelColor: _primary,
          unselectedLabelColor: _muted,
          tabs: [
            Tab(text: 'Participantes${_pending.isNotEmpty ? " (${_pending.length})" : ""}'),
            const Tab(text: 'Admins'),
            const Tab(text: 'Configurações'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : TabBarView(
              controller: _tab,
              children: [
                _buildParticipants(),
                _buildAdmins(),
                _buildConfig(),
              ],
            ),
    );
  }

  // ── aba participantes ──────────────────────────────────────
  Widget _buildParticipants() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: _bg,
            child: TabBar(
              indicatorColor: _primary,
              labelColor: _primary,
              unselectedLabelColor: _muted,
              tabs: [
                Tab(text: 'Pendentes (${_pending.length})'),
                Tab(text: 'Aprovados (${_approved.length})'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(children: [
              // pendentes
              _pending.isEmpty
                  ? const Center(child: Text('Nenhuma solicitação pendente.', style: TextStyle(color: _muted)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _pending.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _MemberTile(
                        member: _pending[i],
                        coinName: _t.coinName,
                        isCoinMode: _t.isCoinMode,
                        onApprove: () => _approve(_pending[i].userId),
                        onReject: () => _reject(_pending[i].userId),
                      ),
                    ),
              // aprovados
              _approved.isEmpty
                  ? const Center(child: Text('Nenhum participante aprovado.', style: TextStyle(color: _muted)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _approved.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _MemberTile(
                        member: _approved[i],
                        coinName: _t.coinName,
                        isCoinMode: _t.isCoinMode,
                        onAddCoins: _t.isCoinMode ? () => _showAddCoins(_approved[i]) : null,
                      ),
                    ),
            ]),
          ),
        ],
      ),
    );
  }

  // ── aba admins ─────────────────────────────────────────────
  Widget _buildAdmins() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._admins.map((a) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: a.isOwner ? _gold.withValues(alpha: 0.3) : _primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: (a.isOwner ? _gold : _primary).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                a.isOwner ? Icons.shield : Icons.admin_panel_settings,
                color: a.isOwner ? _gold : _primary, size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(a.username,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  if (a.userId == _currentUserId)
                    const Text(' (você)', style: TextStyle(fontSize: 12, color: _muted)),
                ]),
                _Chip(label: a.isOwner ? 'Owner' : 'Admin',
                    color: a.isOwner ? _gold : _primary),
              ],
            )),
            if (_isOwner && !a.isOwner)
              IconButton(
                icon: const Icon(Icons.person_remove_outlined, color: _red, size: 20),
                onPressed: () => _removeAdmin(a),
              ),
          ]),
        )),
        if (_isOwner) ...[
          const SizedBox(height: 16),
          const Text('Adicionar admin',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _primary)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDec('Email do usuário'),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _addingAdmin ? null : _addAdmin,
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _addingAdmin
                  ? const SizedBox(height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Adicionar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 6),
          const Text('O usuário precisa ter conta no app.',
              style: TextStyle(fontSize: 11, color: _muted)),
        ],
      ],
    );
  }

  // ── suspender / reabrir todos os eventos ───────────────────
  Future<void> _setAllEventsStatus(String targetStatus) async {
    final fromStatus = targetStatus == 'closed' ? 'open' : 'closed';
    final label = targetStatus == 'closed' ? 'Suspender apostas' : 'Reabrir apostas';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(label),
        content: Text(
          targetStatus == 'closed'
              ? 'Todos os eventos abertos serão fechados. Ninguém mais poderá apostar até você reabrir.'
              : 'Todos os eventos fechados voltarão a aceitar apostas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar', style: TextStyle(color: _muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(
              backgroundColor: targetStatus == 'closed' ? Colors.orange : _primary,
              foregroundColor: Colors.black,
            ),
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      // busca categorias do torneio
      final cats = await Supabase.instance.client
          .from('categories')
          .select('id')
          .eq('tournament_id', _t.id);
      final catIds = (cats as List).map((c) => c['id'] as String).toList();
      if (catIds.isEmpty) return;

      // atualiza todos os eventos com o status desejado
      final updated = await Supabase.instance.client
          .from('events')
          .update({'status': targetStatus})
          .eq('status', fromStatus)
          .inFilter('category_id', catIds)
          .select('id');

      if (mounted) {
        final count = (updated as List).length;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(targetStatus == 'closed'
              ? '🔒 $count evento${count != 1 ? 's' : ''} suspenso${count != 1 ? 's' : ''}!'
              : '🔓 $count evento${count != 1 ? 's' : ''} reaberto${count != 1 ? 's' : ''}!'),
          backgroundColor: targetStatus == 'closed' ? Colors.orange : _primary,
        ));
        widget.onChanged?.call();
      }
    } catch (e) {
      debugPrint('ERRO [tournament_admin_screen.dart]: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── aba configurações ──────────────────────────────────────
  Widget _buildConfig() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ConfigSection(title: 'Torneio', items: [
          _ConfigItem(
            icon: Icons.description_outlined,
            label: 'Descrição / Premiação',
            value: _t.description?.isNotEmpty == true ? _t.description! : 'Não definida',
            onTap: _editDescription,
          ),
          _ConfigItem(
            icon: Icons.lock_outline,
            label: 'Código de acesso',
            value: _t.hasVotingCode ? _t.votingCode! : 'Livre (sem código)',
            onTap: _editVotingCode,
          ),
          _ConfigItem(
            icon: _t.isCoinMode ? Icons.monetization_on_outlined : Icons.gps_fixed,
            label: 'Modo',
            value: _t.isCoinMode
                ? '🪙 Moeda — ${_t.coinName} (${_t.initialCoins} iniciais)'
                : '🎯 Palpite',
            onTap: null, // modo não editável após criação
          ),
        ]),
        const SizedBox(height: 20),
        _ConfigSection(title: 'Apostas', items: [
          _ConfigItem(
            icon: Icons.lock_outline,
            label: 'Suspender todas as apostas',
            value: 'Fecha todos os eventos abertos de uma vez',
            onTap: () => _setAllEventsStatus('closed'),
            color: Colors.orange,
          ),
          _ConfigItem(
            icon: Icons.lock_open_outlined,
            label: 'Reabrir todas as apostas',
            value: 'Reabre todos os eventos fechados de uma vez',
            onTap: () => _setAllEventsStatus('open'),
            color: _primary,
          ),
        ]),
        const SizedBox(height: 20),
        _ConfigSection(title: 'Ações', items: [
          _ConfigItem(
            icon: Icons.emoji_events_outlined,
            label: 'Premiar campeões',
            value: 'Distribui badges 🥇🥈🥉 para o top 3',
            onTap: _awardChampions,
            color: _gold,
          ),
        ]),
      ],
    );
  }
}

// ── widgets auxiliares ───────────────────────────────────────

class _MemberTile extends StatelessWidget {
  final _Member member;
  final String coinName;
  final bool isCoinMode;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onAddCoins;

  const _MemberTile({
    required this.member,
    required this.coinName,
    required this.isCoinMode,
    this.onApprove,
    this.onReject,
    this.onAddCoins,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = member.status == 'pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        _Avatar(username: member.username, color: _primary),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(member.username,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            if (isCoinMode && !isPending)
              Text(
                '${member.coins} $coinName${member.coins != 1 ? 's' : ''}'
                ' · lucro: ${member.profit >= 0 ? '+' : ''}${member.profit}',
                style: const TextStyle(fontSize: 11, color: _muted),
              )
            else
              Text(
                'Solicitou ${_fmt(member.joinedAt)}',
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
          ],
        )),
        if (isPending) ...[
          GestureDetector(
            onTap: onReject,
            child: _ActionBtn(icon: Icons.close, color: Colors.red),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onApprove,
            child: _ActionBtn(icon: Icons.check, color: _primary),
          ),
        ] else if (onAddCoins != null)
          GestureDetector(
            onTap: onAddCoins,
            child: _ActionBtn(icon: Icons.add, color: _primary),
          ),
      ]),
    );
  }

  String _fmt(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return 'há ${diff.inDays}d';
    if (diff.inHours > 0) return 'há ${diff.inHours}h';
    return 'há ${diff.inMinutes}min';
  }
}

class _Avatar extends StatelessWidget {
  final String username;
  final Color color;
  const _Avatar({required this.username, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 38, height: 38,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
    child: Center(
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
      ),
    ),
  );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _ActionBtn({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 36, height: 36,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Icon(icon, color: color, size: 18),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );
}

class _ConfigSection extends StatelessWidget {
  final String title;
  final List<Widget> items;
  const _ConfigSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title.toUpperCase(),
          style: const TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800,
              letterSpacing: 1.2, color: _muted)),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(children: items
            .asMap()
            .entries
            .map((e) => Column(children: [
                  e.value,
                  if (e.key < items.length - 1)
                    const Divider(height: 1, color: _border),
                ]))
            .toList()),
      ),
    ],
  );
}

class _ConfigItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Color? color;

  const _ConfigItem({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? _primary;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: onTap != null ? c : _muted, size: 20),
      title: Text(label,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: onTap != null ? Colors.white : _muted)),
      subtitle: Text(value, style: const TextStyle(fontSize: 11, color: _muted)),
      trailing: onTap != null
          ? const Icon(Icons.chevron_right, color: _muted, size: 18)
          : null,
    );
  }
}
