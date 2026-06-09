import 'package:flutter/material.dart';
import '../utils/error_utils.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tournament.dart';
import '../models/category_model.dart';
import '../models/event.dart';
import '../widgets/app_logo.dart';
import '../widgets/event_card.dart';
import 'tournament_admin_screen.dart';
import 'create_category_screen.dart';
import 'create_event_screen.dart';

const _bg = Color(0xFF0D1117);
const _card = Color(0xFF161B22);
const _primary = Color(0xFF00C851);
const _gold = Color(0xFFD4A017);
const _border = Color(0xFF30363D);
const _muted = Color(0xFF8B949E);

class _CategoryWithEvents {
  final TournamentCategory category;
  final List<Event> events;
  _CategoryWithEvents({required this.category, required this.events});
}

class _LeaderEntry {
  final String userId;
  final String username;
  final int wins;
  final int total;
  _LeaderEntry({required this.userId, required this.username, required this.wins, required this.total});
}

class TournamentDetailScreen extends StatefulWidget {
  final Tournament tournament;

  const TournamentDetailScreen({super.key, required this.tournament});

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> {
  List<_CategoryWithEvents> _sections = [];
  List<_LeaderEntry> _top3 = [];
  Map<String, List<String>> _votedOptions = {}; // eventId → [optionIds]
  String? _filterCategoryId;
  String? _filterStatus; // null = todos, 'open', 'closed', 'resolved'
  bool _loading = true;
  String? _adminRole;
  String? _memberStatus; // null = não membro, 'pending', 'approved', 'rejected'
  bool _joining = false;

  bool get _isAdmin => _adminRole != null;
  bool get _isOwner => _adminRole == 'owner';
  bool get _isApprovedMember => _memberStatus == 'approved';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    try {
      final categoriesData = await Supabase.instance.client
          .from('categories')
          .select()
          .eq('tournament_id', widget.tournament.id)
          .order('created_at', ascending: true);

      final categories = (categoriesData as List)
          .map((c) => TournamentCategory.fromJson(c))
          .toList();

      // busca todos os eventos das categorias deste torneio de uma vez
      final eventsData = categories.isEmpty
          ? []
          : await Supabase.instance.client
              .from('events')
              .select('*, options!options_event_id_fkey(*)')
              .inFilter('category_id', categories.map((c) => c.id).toList())
              .order('created_at', ascending: true);

      final eventsByCat = <String, List<Event>>{};
      for (final row in eventsData) {
        final e = Event.fromJson(row);
        if (e.categoryId != null) {
          eventsByCat.putIfAbsent(e.categoryId!, () => []).add(e);
        }
      }

      String? adminRole;
      String? memberStatus;
      if (userId != null) {
        final adminData = await Supabase.instance.client
            .from('tournament_admins')
            .select('role')
            .eq('tournament_id', widget.tournament.id)
            .eq('user_id', userId)
            .maybeSingle();
        adminRole = adminData?['role'] as String?;

        final memberData = await Supabase.instance.client
            .from('tournament_members')
            .select('status')
            .eq('tournament_id', widget.tournament.id)
            .eq('user_id', userId)
            .maybeSingle();
        memberStatus = memberData?['status'] as String?;
      }

      // top 3 leaderboard
      List<_LeaderEntry> top3 = [];
      try {
        if (widget.tournament.isCoinMode) {
          // modo moeda: ordena por lucro
          final membersData = await Supabase.instance.client
              .from('tournament_members')
              .select('user_id, coins, initial_coins, bonus_coins, profiles!inner(username)')
              .eq('tournament_id', widget.tournament.id)
              .eq('status', 'approved');

          top3 = (membersData as List).map((m) => _LeaderEntry(
            userId:       m['user_id'] as String,
            username:     (m['profiles'] as Map)['username'] as String? ?? 'Usuário',
            wins:         (m['coins'] as int? ?? 0) - (m['initial_coins'] as int? ?? 0) - (m['bonus_coins'] as int? ?? 0),
            total:        m['coins'] as int? ?? 0,
          )).toList()
            ..sort((a, b) => b.wins.compareTo(a.wins));
          if (top3.length > 3) top3 = top3.sublist(0, 3);
        } else {
          // modo palpite: ordena por acertos
          final allEventIds = eventsByCat.values
              .expand((evs) => evs.map((e) => e.id))
              .toList();

          if (allEventIds.isNotEmpty) {
            final betsData = await Supabase.instance.client
                .from('bets')
                .select('user_id, status, profiles!inner(username)')
                .inFilter('event_id', allEventIds);

            final map = <String, _LeaderEntry>{};
            for (final row in betsData as List) {
              final uid    = row['user_id'] as String;
              final status = row['status'] as String;
              final uname  = (row['profiles'] as Map)['username'] as String? ?? 'Usuário';
              final e = map[uid] ?? _LeaderEntry(userId: uid, username: uname, wins: 0, total: 0);
              map[uid] = _LeaderEntry(
                userId: uid, username: uname,
                wins:  e.wins  + (status == 'won' ? 1 : 0),
                total: e.total + 1,
              );
            }
            top3 = map.values.toList()
              ..sort((a, b) => b.wins != a.wins
                  ? b.wins.compareTo(a.wins)
                  : (b.total > 0 ? b.wins / b.total : 0)
                      .compareTo(a.total > 0 ? a.wins / a.total : 0));
            if (top3.length > 3) top3 = top3.sublist(0, 3);
          }
        }
      } catch (_) {}

      // busca eventos votados pelo usuário (suporta múltiplas apostas por evento)
      Map<String, List<String>> votedIds = {};
      if (userId != null) {
        final betsData = await Supabase.instance.client
            .from('bets')
            .select('event_id, option_id')
            .eq('user_id', userId);
        for (final b in betsData as List) {
          final eid = b['event_id'] as String;
          final oid = b['option_id'] as String;
          votedIds.putIfAbsent(eid, () => []).add(oid);
        }
      }

      if (mounted) {
        setState(() {
          _votedOptions = votedIds;
          _sections = categories
              .map((c) => _CategoryWithEvents(
                    category: c,
                    events: eventsByCat[c.id] ?? [],
                  ))
              .toList();
          _top3 = top3;
          _adminRole = adminRole;
          _memberStatus = memberStatus;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ERRO load tournament detail: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _awardChampions() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Premiar Campeões'),
        content: const Text(
            'Isso vai distribuir os badges 🥇🥈🥉 para o top 3 do leaderboard atual. Pode ser feito mais de uma vez — os badges serão atualizados.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: _muted)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final result = await Supabase.instance.client.rpc(
                  'award_tournament_champions',
                  params: {'p_tournament_id': widget.tournament.id},
                );
                if (mounted) {
                  final awarded = (result as List).length;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('$awarded campeão(ões) premiado(s)! 🏆'),
                    backgroundColor: _gold,
                  ));
                }
              } catch (e) {
      debugPrint('ERRO [tournament_detail_screen.dart]: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
                backgroundColor: _gold, foregroundColor: Colors.black),
            child: const Text('Premiar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openEvent(Event event, String breadcrumb) {
    context.push('/evento/${event.id}').then((_) => _load());
  }

  void _editDescription() {
    final ctrl = TextEditingController(
        text: widget.tournament.description ?? '');
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
            const Text('Descrição / Premiação',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Descreva o torneio, as regras e a premiação para os vencedores.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'Ex: 1º lugar ganha troféu + R\$100. 2º lugar...',
                hintStyle: const TextStyle(color: _muted),
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
                final text = ctrl.text.trim();
                Navigator.pop(context);
                try {
                  await Supabase.instance.client
                      .from('tournaments')
                      .update({'description': text.isEmpty ? null : text})
                      .eq('id', widget.tournament.id);
                  _load();
                } catch (e) {
      debugPrint('ERRO [tournament_detail_screen.dart]: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
                    );
                  }
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

  void _editVotingCode() {
    final ctrl = TextEditingController(
        text: widget.tournament.votingCode ?? '');
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
            const Text('Código de Votação',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Defina um código que os participantes precisam inserir antes de votar. Deixe em branco para votação livre.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Ex: TENIS2025',
                hintStyle: const TextStyle(color: _muted),
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
                final code = ctrl.text.trim().toUpperCase();
                Navigator.pop(context);
                try {
                  await Supabase.instance.client
                      .from('tournaments')
                      .update({'voting_code': code.isEmpty ? null : code})
                      .eq('id', widget.tournament.id);
                  _load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(code.isEmpty
                          ? 'Código removido — votação livre.'
                          : 'Código definido: $code'),
                      backgroundColor: _primary,
                    ));
                  }
                } catch (e) {
      debugPrint('ERRO [tournament_detail_screen.dart]: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
                  }
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

  Future<void> _joinTournament() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      context.push('/auth?redirect=${Uri.encodeComponent('/torneio/${widget.tournament.slug ?? widget.tournament.id}')}');
      return;
    }

    String? code;
    final hasCode = widget.tournament.votingCode != null && widget.tournament.votingCode!.isNotEmpty;
    if (hasCode) {
      final ctrl = TextEditingController();
      String? err;
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => AlertDialog(
            backgroundColor: _card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Text('🔒 ', style: TextStyle(fontSize: 20)),
              Text('Código de acesso'),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Este torneio exige um código para entrar.',
                  style: TextStyle(color: _muted, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'Digite o código',
                  errorText: err,
                  filled: true, fillColor: _bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _primary)),
                ),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar', style: TextStyle(color: _muted))),
              FilledButton(
                onPressed: () {
                  if (ctrl.text.trim().toUpperCase() == widget.tournament.votingCode!.toUpperCase()) {
                    Navigator.pop(ctx, true);
                  } else {
                    set(() => err = 'Código incorreto');
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.black),
                child: const Text('Entrar', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
      if (ok != true) return;
      code = ctrl.text.trim();
    }

    setState(() => _joining = true);
    try {
      final result = await Supabase.instance.client.rpc('join_tournament', params: {
        'p_tournament_id': widget.tournament.id,
        if (code != null) 'p_voting_code': code,
      }) as String;

      if (mounted) {
        setState(() => _memberStatus = result);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result == 'approved'
              ? '✅ Você entrou no torneio!'
              : '⏳ Solicitação enviada! Aguarde aprovação do admin.'),
          backgroundColor: result == 'approved' ? _primary : _gold,
        ));
        if (result == 'approved') _load();
      }
    } catch (e) {
      debugPrint('ERRO [tournament_detail_screen.dart]: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _openCreateCategory() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateCategoryScreen(tournamentId: widget.tournament.id),
      ),
    );
    if (created == true) _load();
  }

  void _openCreateEvent(String categoryId) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateEventScreen(
          categoryId: categoryId,
          isCoinMode: widget.tournament.isCoinMode,
          coinName: widget.tournament.coinName,
        ),
      ),
    );
    if (created == true) _load();
  }

  void _deleteCategory(TournamentCategory cat) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Deletar categoria'),
        content: Text('Deletar "${cat.name}" e todos os eventos dentro dela?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: _muted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await Supabase.instance.client
                    .from('categories')
                    .delete()
                    .eq('id', cat.id);
                _load();
              } catch (e) {
      debugPrint('ERRO [tournament_detail_screen.dart]: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Deletar',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _DetailAppBar(
              title: widget.tournament.name,
              subtitle: widget.tournament.isActive ? 'Ativo' : 'Encerrado',
              isActive: widget.tournament.isActive,
              onBack: () => context.canPop() ? context.pop() : context.go('/'),
              onLeaderboard: () => context.push('/torneio/${widget.tournament.slug ?? widget.tournament.id}/leaderboard'),
              onAdminPanel: _isAdmin
                  ? () => Navigator.of(context)
                      .push(MaterialPageRoute(
                          builder: (_) => TournamentAdminScreen(
                                tournament: widget.tournament,
                                onChanged: _load,
                              )))
                      .then((_) => _load())
                  : null,
            ),
            // Banner de participação (só para não-admins)
            if (!_loading && !_isAdmin) _MembershipBanner(
              status: _memberStatus,
              isCoinMode: widget.tournament.isCoinMode,
              coinName: widget.tournament.coinName,
              joining: _joining,
              onJoin: _joinTournament,
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : RefreshIndicator(
                      color: _primary,
                      onRefresh: _load,
                      child: _sections.isEmpty
                          ? _emptyState()
                          : _body(),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _openCreateCategory,
              backgroundColor: _primary,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add),
              label: const Text('Categoria',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  Widget _descriptionCard() {
    final desc = widget.tournament.description;
    final hasDesc = desc != null && desc.isNotEmpty;

    if (!hasDesc && !_isAdmin) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _isAdmin ? _editDescription : null,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasDesc ? _gold.withValues(alpha: 0.3) : _border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('🏅',  style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('PREMIAÇÃO & REGRAS',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: _gold)),
              ),
              if (_isAdmin)
                const Icon(Icons.edit_outlined, color: _muted, size: 14),
            ]),
            const SizedBox(height: 10),
            if (hasDesc)
              Text(desc,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.white, height: 1.5))
            else
              const Text(
                'Toque para adicionar descrição e premiação do torneio.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _descriptionCard(),
        if (_top3.isNotEmpty) _LeaderboardCard(
          top3: _top3,
          isCoinMode: widget.tournament.isCoinMode,
          coinName: widget.tournament.coinName,
          onViewAll: () => context.push('/torneio/${widget.tournament.slug ?? widget.tournament.id}/leaderboard'),
        ),
        const SizedBox(height: 80),
        Center(
          child: Text(
            _isAdmin
                ? 'Nenhuma categoria ainda.\nCrie a primeira!'
                : 'Nenhuma categoria ainda.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted),
          ),
        ),
      ],
    );
  }

  Widget _body() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _descriptionCard(),
        ),
        if (_top3.isNotEmpty) Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _LeaderboardCard(
            top3: _top3,
            isCoinMode: widget.tournament.isCoinMode,
            coinName: widget.tournament.coinName,
            onViewAll: () => context.push('/torneio/${widget.tournament.slug ?? widget.tournament.id}/leaderboard'),
          ),
        ),
        // chips de filtro por categoria
        if (_sections.length > 1)
          _CategoryFilterRow(
            sections: _sections,
            selectedId: _filterCategoryId,
            onTap: (id) => setState(() =>
                _filterCategoryId = _filterCategoryId == id ? null : id),
          ),
        // chips de filtro por status
        _StatusFilterRow(
          sections: _sections,
          filterCategoryId: _filterCategoryId,
          selected: _filterStatus,
          onTap: (s) => setState(() => _filterStatus = (s == null || _filterStatus == s) ? null : s),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
        ..._sections
            .where((s) => _filterCategoryId == null || s.category.id == _filterCategoryId)
            .map((s) => _CategorySection(
              section: s,
              isAdmin: _isAdmin,
              tournamentName: widget.tournament.name,
              onTapEvent: (e, b) => _openEvent(e, b),
              onCreateEvent: () => _openCreateEvent(s.category.id),
              onDeleteCategory: _isAdmin ? () => _deleteCategory(s.category) : null,
              votedOptions: _votedOptions,
              onBreadcrumbTap: () => setState(() =>
                _filterCategoryId = _filterCategoryId == s.category.id ? null : s.category.id,
              ),
              isCoinMode: widget.tournament.isCoinMode,
              coinName: widget.tournament.coinName,
              filterStatus: _filterStatus,
            )).toList(),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryFilterRow extends StatelessWidget {
  final List<_CategoryWithEvents> sections;
  final String? selectedId;
  final void Function(String) onTap;

  const _CategoryFilterRow({
    required this.sections,
    required this.selectedId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: sections.length,
        itemBuilder: (_, i) {
          final cat = sections[i].category;
          final active = selectedId == cat.id;
          return GestureDetector(
            onTap: () => onTap(cat.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? _primary : _card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? _primary : _border),
              ),
              child: Text(
                cat.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: active ? Colors.black : _muted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatusFilterRow extends StatelessWidget {
  final List<_CategoryWithEvents> sections;
  final String? filterCategoryId;
  final String? selected;
  final void Function(String?) onTap;

  const _StatusFilterRow({
    required this.sections,
    required this.filterCategoryId,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final events = sections
        .where((s) => filterCategoryId == null || s.category.id == filterCategoryId)
        .expand((s) => s.events)
        .toList();

    final open     = events.where((e) => e.isOpen).length;
    final closed   = events.where((e) => !e.isOpen && e.status != 'resolved').length;
    final resolved = events.where((e) => e.status == 'resolved').length;

    if (events.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          _statusChip('Todos', events.length, null, _muted),
          const SizedBox(width: 8),
          _statusChip('Abertos', open, 'open', _primary),
          const SizedBox(width: 8),
          _statusChip('Fechados', closed, 'closed', Colors.orange),
          const SizedBox(width: 8),
          _statusChip('Encerrados', resolved, 'resolved', _gold),
        ],
      ),
    );
  }

  Widget _statusChip(String label, int count, String? value, Color color) {
    final active = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.18) : color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.7) : color.withValues(alpha: 0.3),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: active ? color : color.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w900 : FontWeight.w600)),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: active ? 0.25 : 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: color, fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardCard extends StatelessWidget {
  final List<_LeaderEntry> top3;
  final VoidCallback onViewAll;
  final bool isCoinMode;
  final String coinName;

  const _LeaderboardCard({
    required this.top3,
    required this.onViewAll,
    required this.isCoinMode,
    required this.coinName,
  });

  static const _medals = ['🥇', '🥈', '🥉'];
  static const _colors = [_gold, Color(0xFFC0C0C0), Color(0xFFCD7F32)];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('LEADERBOARD',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                    letterSpacing: 1.5, color: _gold)),
            const Spacer(),
            GestureDetector(
              onTap: onViewAll,
              child: const Text('Ver todos →',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _muted)),
            ),
          ]),
          const SizedBox(height: 12),
          ...top3.asMap().entries.map((e) {
            final rank  = e.key;
            final entry = e.value;
            final color = _colors[rank];

            final String mainText;
            final String subText;
            if (isCoinMode) {
              final profit = entry.wins; // wins = lucro no modo coin (reaproveitado)
              mainText = '${profit >= 0 ? '+' : ''}$profit $coinName${profit.abs() != 1 ? 's' : ''}';
              subText  = '${entry.total} atual'; // total = coins atual
            } else {
              mainText = '${entry.wins} acertos';
              subText  = entry.total > 0
                  ? '${(entry.wins / entry.total * 100).round()}%' : '—';
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Text(_medals[rank], style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(child: Text(entry.username,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis)),
                Text(mainText,
                    style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text(subText, style: const TextStyle(fontSize: 11, color: _muted)),
              ]),
            );
          }),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final _CategoryWithEvents section;
  final bool isAdmin;
  final String tournamentName;
  final void Function(Event, String) onTapEvent;
  final VoidCallback onCreateEvent;
  final VoidCallback? onDeleteCategory;
  final Map<String, List<String>> votedOptions;
  final VoidCallback? onBreadcrumbTap;
  final bool isCoinMode;
  final String coinName;
  final String? filterStatus;

  const _CategorySection({
    required this.section,
    required this.isAdmin,
    required this.tournamentName,
    required this.onTapEvent,
    required this.onCreateEvent,
    this.onDeleteCategory,
    required this.votedOptions, // eventId → [optionIds]
    this.onBreadcrumbTap,
    this.isCoinMode = false,
    this.coinName = 'Ficha',
    this.filterStatus,
  });

  @override
  Widget build(BuildContext context) {
    final breadcrumb = '$tournamentName › ${section.category.name}';
    final visibleEvents = filterStatus == null
        ? section.events
        : section.events.where((e) {
            if (filterStatus == 'open')     return e.isOpen;
            if (filterStatus == 'closed')   return !e.isOpen && e.status != 'resolved';
            if (filterStatus == 'resolved') return e.status == 'resolved';
            return true;
          }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // cabeçalho da categoria
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  section.category.name.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: _muted,
                  ),
                ),
              ),
              if (isAdmin) ...[
                GestureDetector(
                  onTap: onCreateEvent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _primary.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, color: _primary, size: 13),
                        SizedBox(width: 3),
                        Text('Evento',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _primary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDeleteCategory,
                  child: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                ),
              ],
            ],
          ),
        ),
        if (visibleEvents.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              section.events.isEmpty
                  ? (isAdmin ? 'Nenhum evento. Toque em "+ Evento" para criar.' : 'Nenhum evento ainda.')
                  : 'Nenhum evento neste filtro.',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth > 500
                  ? (constraints.maxWidth - 20) / 3
                  : (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: visibleEvents.map((event) => SizedBox(
                  width: cardWidth,
                  child: EventCard(
                    event: event,
                    breadcrumb: breadcrumb,
                    onTap: () => onTapEvent(event, breadcrumb),
                    voted: votedOptions.containsKey(event.id),
                    votedOptionIds: votedOptions[event.id] ?? [],
                    onBreadcrumbTap: onBreadcrumbTap,
                    isCoinMode: isCoinMode,
                    coinName: coinName,
                  ),
                )).toList(),
              );
            },
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// _GridEventCard removido — usar EventCard de widgets/event_card.dart

class _RemovedGridEventCard extends StatelessWidget {
  final Event event;
  final String breadcrumb;
  final VoidCallback onTap;

  const _RemovedGridEventCard(
      {required this.event, required this.breadcrumb, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final total = event.totalPredictions;
    final isResolved = event.status == 'resolved';
    final opts = [...event.options]
      ..sort((a, b) => b.predictionCount.compareTo(a.predictionCount));

    Color borderColor = isResolved
        ? _gold.withValues(alpha: 0.3)
        : event.isOpen
            ? _primary.withValues(alpha: 0.25)
            : _border;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // breadcrumb + status dot
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                width: 6, height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: isResolved ? _gold : event.isOpen ? _primary : _muted,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  breadcrumb.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 8, fontWeight: FontWeight.w800,
                      letterSpacing: 0.8, color: _muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              event.title,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            // até 4 opções
            ...opts.take(4).toList().asMap().entries.map((entry) {
              final isWinner = event.winningOptionId == opts[entry.key].id;
              final o = entry.value;
              final pct = total > 0
                  ? (o.predictionCount / total * 100).round()
                  : 0;
              final leadPct = total > 0
                  ? (opts.first.predictionCount / total * 100).round()
                  : 0;
              final isLeading = pct > 0 && pct == leadPct;
              final fillColor = isWinner
                  ? _gold.withValues(alpha: 0.25)
                  : isLeading
                      ? _primary.withValues(alpha: 0.22)
                      : _muted.withValues(alpha: 0.12);
              final textColor = isWinner ? _gold : isLeading ? _primary : _muted;

              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                height: 26,
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _border.withValues(alpha: 0.7)),
                ),
                clipBehavior: Clip.hardEdge,
                child: Stack(children: [
                  if (total > 0)
                    FractionallySizedBox(
                      widthFactor: (pct / 100).clamp(0.0, 1.0),
                      child: Container(color: fillColor),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(o.title,
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          total > 0 ? '$pct%' : '—',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: textColor),
                        ),
                      ],
                    ),
                  ),
                ]),
              );
            }),
            if (opts.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('+${opts.length - 4} mais',
                    style: const TextStyle(fontSize: 9, color: _muted)),
              ),
            const Spacer(),
            // rodapé votar / resolvido
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: isResolved
                    ? _gold.withValues(alpha: 0.08)
                    : event.isOpen
                        ? _primary.withValues(alpha: 0.12)
                        : _muted.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isResolved
                      ? _gold.withValues(alpha: 0.3)
                      : event.isOpen
                          ? _primary.withValues(alpha: 0.3)
                          : _border,
                ),
              ),
              child: Center(
                child: Text(
                  isResolved ? 'RESOLVIDO' : event.isOpen ? 'VOTAR' : 'FECHADO',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: isResolved ? _gold : event.isOpen ? _primary : _muted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Banner de participação
class _MembershipBanner extends StatelessWidget {
  final String? status; // null = não membro
  final bool isCoinMode;
  final String coinName;
  final bool joining;
  final VoidCallback onJoin;

  const _MembershipBanner({
    required this.status,
    required this.isCoinMode,
    required this.coinName,
    required this.joining,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    // aprovado: sem banner
    if (status == 'approved') return const SizedBox.shrink();

    final Color color;
    final String icon;
    final String title;
    final String subtitle;
    final bool showButton;

    if (status == 'pending') {
      color = _gold;
      icon = '⏳';
      title = 'Aguardando aprovação';
      subtitle = 'O admin precisa aprovar sua entrada antes de você votar.';
      showButton = false;
    } else if (status == 'rejected') {
      color = Colors.red;
      icon = '🚫';
      title = 'Acesso negado';
      subtitle = 'Sua solicitação foi recusada pelo organizador.';
      showButton = false;
    } else {
      // null — não membro
      color = _primary;
      icon = '🎯';
      title = 'Participe deste torneio';
      subtitle = isCoinMode
          ? 'Entre para receber suas $coinName${coinName.endsWith('s') ? '' : 's'} e começar a apostar!'
          : 'Entre para registrar seus palpites e aparecer no ranking!';
      showButton = true;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(fontSize: 11, color: _muted)),
          ]),
        ),
        if (showButton) ...[
          const SizedBox(width: 10),
          joining
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _primary))
              : FilledButton(
                  onPressed: onJoin,
                  style: FilledButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Entrar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
        ],
      ]),
    );
  }
}

// AppBar
class _DetailAppBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isActive;
  final VoidCallback onBack;
  final VoidCallback onLeaderboard;
  final VoidCallback? onAdminPanel;

  const _DetailAppBar({
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.onBack,
    required this.onLeaderboard,
    this.onAdminPanel,
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
                borderRadius: BorderRadius.circular(18),
              ),
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
                Text(
                  subtitle.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: isActive ? _primary : _muted,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onLeaderboard,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.leaderboard_outlined, color: _muted, size: 18),
            ),
          ),
          if (onAdminPanel != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAdminPanel,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  border: Border.all(color: _primary.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.settings_outlined, color: _primary, size: 18),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
