import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tournament.dart';
import '../models/category_model.dart';
import '../models/event.dart';
import 'admins_screen.dart';
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
  bool _loading = true;
  String? _adminRole;

  bool get _isAdmin => _adminRole != null;
  bool get _isOwner => _adminRole == 'owner';

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
      if (userId != null) {
        final adminData = await Supabase.instance.client
            .from('tournament_admins')
            .select('role')
            .eq('tournament_id', widget.tournament.id)
            .eq('user_id', userId)
            .maybeSingle();
        adminRole = adminData?['role'] as String?;
      }

      // top 3 leaderboard
      List<_LeaderEntry> top3 = [];
      try {
        final resolvedEventIds = eventsByCat.values
            .expand((evs) => evs.where((e) => e.status == 'resolved').map((e) => e.id))
            .toList();

        if (resolvedEventIds.isNotEmpty) {
          final betsData = await Supabase.instance.client
              .from('bets')
              .select('user_id, status, profiles!inner(username)')
              .inFilter('event_id', resolvedEventIds)
              .neq('status', 'pending');

          final map = <String, _LeaderEntry>{};
          for (final row in betsData as List) {
            final uid = row['user_id'] as String;
            final status = row['status'] as String;
            final uname = (row['profiles'] as Map)['username'] as String? ?? 'Usuário';
            final e = map[uid] ?? _LeaderEntry(userId: uid, username: uname, wins: 0, total: 0);
            map[uid] = _LeaderEntry(
              userId: uid, username: uname,
              wins: e.wins + (status == 'won' ? 1 : 0),
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
      } catch (_) {}

      if (mounted) {
        setState(() {
          _sections = categories
              .map((c) => _CategoryWithEvents(
                    category: c,
                    events: eventsByCat[c.id] ?? [],
                  ))
              .toList();
          _top3 = top3;
          _adminRole = adminRole;
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
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
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
    context.push('/evento/${event.id}');
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
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
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
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
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
        builder: (_) => CreateEventScreen(categoryId: categoryId),
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
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
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
              onLeaderboard: () => context.push('/torneio/${widget.tournament.id}/leaderboard'),
              onVotingCode: _isOwner ? _editVotingCode : null,
              onAward: _isOwner ? _awardChampions : null,
              onAdmins: _isOwner
                  ? () => Navigator.of(context)
                      .push(MaterialPageRoute(
                          builder: (_) =>
                              AdminsScreen(tournament: widget.tournament)))
                      .then((_) => _load())
                  : null,
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
          onViewAll: () => context.push('/torneio/${widget.tournament.id}/leaderboard'),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        _descriptionCard(),
        if (_top3.isNotEmpty) _LeaderboardCard(
          top3: _top3,
          onViewAll: () => context.push('/torneio/${widget.tournament.id}/leaderboard'),
        ),
        ..._sections.map((s) => _CategorySection(
              section: s,
              isAdmin: _isAdmin,
              tournamentName: widget.tournament.name,
              onTapEvent: (e, b) => _openEvent(e, b),
              onCreateEvent: () => _openCreateEvent(s.category.id),
              onDeleteCategory: _isAdmin ? () => _deleteCategory(s.category) : null,
            )).toList(),
      ],
    );
  }
}

class _LeaderboardCard extends StatelessWidget {
  final List<_LeaderEntry> top3;
  final VoidCallback onViewAll;

  const _LeaderboardCard({required this.top3, required this.onViewAll});

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
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: _gold)),
            const Spacer(),
            GestureDetector(
              onTap: onViewAll,
              child: const Text('Ver todos →',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _muted)),
            ),
          ]),
          const SizedBox(height: 12),
          ...top3.asMap().entries.map((e) {
            final rank = e.key;
            final entry = e.value;
            final color = _colors[rank];
            final accuracy = entry.total > 0
                ? '${(entry.wins / entry.total * 100).round()}%'
                : '—';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Text(_medals[rank], style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(entry.username,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                ),
                Text('${entry.wins} acertos',
                    style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text(accuracy,
                    style: TextStyle(fontSize: 11, color: _muted)),
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

  const _CategorySection({
    required this.section,
    required this.isAdmin,
    required this.tournamentName,
    required this.onTapEvent,
    required this.onCreateEvent,
    this.onDeleteCategory,
  });

  @override
  Widget build(BuildContext context) {
    final breadcrumb = '$tournamentName › ${section.category.name}';
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
        if (section.events.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              isAdmin ? 'Nenhum evento. Toque em "+ Evento" para criar.' : 'Nenhum evento ainda.',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = (constraints.maxWidth / 200).floor().clamp(2, 4);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 250,
                ),
                itemCount: section.events.length,
                itemBuilder: (_, i) {
                  final event = section.events[i];
                  return _GridEventCard(
                    event: event,
                    breadcrumb: breadcrumb,
                    onTap: () => onTapEvent(event, breadcrumb),
                  );
                },
              );
            },
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _GridEventCard extends StatelessWidget {
  final Event event;
  final String breadcrumb;
  final VoidCallback onTap;

  const _GridEventCard(
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

// AppBar
class _DetailAppBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isActive;
  final VoidCallback onBack;
  final VoidCallback onLeaderboard;
  final VoidCallback? onVotingCode;
  final VoidCallback? onAward;
  final VoidCallback? onAdmins;

  const _DetailAppBar({
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.onBack,
    required this.onLeaderboard,
    this.onVotingCode,
    this.onAward,
    this.onAdmins,
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
          const Text(
            'APOSTINHA',
            style: TextStyle(
              color: _primary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
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
          if (onVotingCode != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onVotingCode,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(child: Text('🔒', style: TextStyle(fontSize: 15))),
              ),
            ),
          ],
          if (onAward != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAward,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  border: Border.all(color: _gold.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(child: Text('🏆', style: TextStyle(fontSize: 16))),
              ),
            ),
          ],
          if (onAdmins != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAdmins,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.group_outlined, color: _muted, size: 18),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
