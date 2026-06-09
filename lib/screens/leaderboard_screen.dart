import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tournament.dart';

const _bg      = Color(0xFF0D1117);
const _card    = Color(0xFF161B22);
const _primary = Color(0xFF00C851);
const _gold    = Color(0xFFD4A017);
const _border  = Color(0xFF30363D);
const _muted   = Color(0xFF8B949E);

// ── modelo unificado de entry ────────────────────────────────
class _Entry {
  final String userId;
  final String username;

  // modo prediction
  final int wins;
  final int total;
  final double points; // SUM(points_earned)

  // modo coin
  final int coins;
  final int initialCoins;
  final int bonusCoins;

  _Entry({
    required this.userId,
    required this.username,
    this.wins = 0,
    this.total = 0,
    this.points = 0,
    this.coins = 0,
    this.initialCoins = 0,
    this.bonusCoins = 0,
  });

  double get accuracy => total > 0 ? wins / total : 0;
  int get profit => coins - initialCoins - bonusCoins;
}

// ════════════════════════════════════════════════════════════
class LeaderboardScreen extends StatefulWidget {
  final Tournament tournament;
  const LeaderboardScreen({super.key, required this.tournament});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<_Entry> _entries = [];
  bool _loading = true;
  String? _currentUserId;

  bool get _isCoin => widget.tournament.isCoinMode;

  @override
  void initState() {
    super.initState();
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final entries = _isCoin ? await _loadCoin() : await _loadPrediction();
      if (mounted) setState(() { _entries = entries; _loading = false; });
    } catch (e) {
      debugPrint('ERRO leaderboard: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── modo prediction ────────────────────────────────────────
  Future<List<_Entry>> _loadPrediction() async {
    final eventIds = await _getEventIds();
    if (eventIds.isEmpty) return [];

    final data = await Supabase.instance.client
        .from('bets')
        .select('user_id, status, points_earned, profiles!inner(username)')
        .inFilter('event_id', eventIds);

    final map = <String, _Entry>{};
    for (final row in data as List) {
      final uid           = row['user_id'] as String;
      final status        = row['status'] as String;
      final pointsEarned  = (row['points_earned'] as num?)?.toDouble() ?? 0;
      final username      = (row['profiles'] as Map)['username'] as String? ?? 'Usuário';
      final e = map[uid] ?? _Entry(userId: uid, username: username);
      map[uid] = _Entry(
        userId:   uid,
        username: username,
        wins:     e.wins   + (status == 'won' ? 1 : 0),
        total:    e.total  + 1,
        points:   e.points + pointsEarned,
      );
    }

    // ordena por pontos totais; desempate por acertos; desempate por precisão
    return map.values.toList()
      ..sort((a, b) {
        if (b.points != a.points) return b.points.compareTo(a.points);
        if (b.wins != a.wins) return b.wins.compareTo(a.wins);
        return b.accuracy.compareTo(a.accuracy);
      });
  }

  // ── modo coin ──────────────────────────────────────────────
  Future<List<_Entry>> _loadCoin() async {
    final data = await Supabase.instance.client
        .from('tournament_members')
        .select('user_id, coins, initial_coins, bonus_coins, profiles!tournament_members_user_id_fkey(username)')
        .eq('tournament_id', widget.tournament.id)
        .eq('status', 'approved');

    final entries = (data as List).map((m) => _Entry(
      userId:       m['user_id'] as String,
      username:     (m['profiles'] as Map)['username'] as String? ?? 'Usuário',
      coins:        m['coins']         as int? ?? 0,
      initialCoins: m['initial_coins'] as int? ?? 0,
      bonusCoins:   m['bonus_coins']   as int? ?? 0,
    )).toList()
      ..sort((a, b) => b.profit.compareTo(a.profit));

    return entries;
  }

  Future<List<String>> _getEventIds() async {
    final cats = await Supabase.instance.client
        .from('categories')
        .select('id')
        .eq('tournament_id', widget.tournament.id);

    if ((cats as List).isEmpty) return [];
    final catIds = cats.map((c) => c['id'] as String).toList();

    final events = await Supabase.instance.client
        .from('events')
        .select('id')
        .inFilter('category_id', catIds);

    return (events as List).map((e) => e['id'] as String).toList();
  }

  // ════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _appBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _primary))
                : RefreshIndicator(
                    color: _primary,
                    onRefresh: _load,
                    child: _entries.isEmpty
                        ? ListView(children: const [
                            SizedBox(height: 120),
                            Center(child: Text(
                              'Nenhum resultado ainda.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _muted),
                            )),
                          ])
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                            children: [
                              if (_entries.length >= 3)
                                _Podium(entries: _entries.take(3).toList(), isCoin: _isCoin,
                                    coinName: widget.tournament.coinName),
                              const SizedBox(height: 20),
                              ..._entries.asMap().entries.map((e) => _LeaderRow(
                                rank: e.key + 1,
                                entry: e.value,
                                isMe: e.value.userId == _currentUserId,
                                isCoin: _isCoin,
                                coinName: widget.tournament.coinName,
                              )),
                            ],
                          ),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _appBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(bottom: BorderSide(color: _border, width: 0.5)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => context.canPop() ? context.pop() : context.go('/'),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.chevron_left, color: _muted, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        const Text('APOSTINHA',
            style: TextStyle(
                color: _primary, fontSize: 18,
                fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Text('LEADERBOARD',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                        letterSpacing: 1.2, color: _gold)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: (_isCoin ? _gold : _primary).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _isCoin ? '🪙 ${widget.tournament.coinName}' : '🎯 Palpite',
                    style: TextStyle(
                        fontSize: 9, fontWeight: FontWeight.bold,
                        color: _isCoin ? _gold : _primary),
                  ),
                ),
              ]),
              Text(widget.tournament.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── pódio ────────────────────────────────────────────────────
class _Podium extends StatelessWidget {
  final List<_Entry> entries;
  final bool isCoin;
  final String coinName;
  const _Podium({required this.entries, required this.isCoin, required this.coinName});

  @override
  Widget build(BuildContext context) {
    final order = [
      if (entries.length > 1) (rank: 2, entry: entries[1]),
      (rank: 1, entry: entries[0]),
      if (entries.length > 2) (rank: 3, entry: entries[2]),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: order.map((item) {
        final isFirst = item.rank == 1;
        final color = item.rank == 1 ? _gold
            : item.rank == 2 ? const Color(0xFFC0C0C0)
            : const Color(0xFFCD7F32);
        final height = isFirst ? 90.0 : 70.0;

        final label = isCoin
            ? '${item.entry.profit >= 0 ? '+' : ''}${item.entry.profit} $coinName${item.entry.profit.abs() != 1 ? 's' : ''}'
            : '${item.entry.points % 1 == 0 ? item.entry.points.toInt() : item.entry.points.toStringAsFixed(1)} pts';

        return Expanded(
          child: Column(children: [
            Container(
              width: isFirst ? 52 : 44,
              height: isFirst ? 52 : 44,
              decoration: BoxDecoration(
                color: _card, shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: Center(child: Text(
                item.entry.username.isNotEmpty
                    ? item.entry.username[0].toUpperCase() : '?',
                style: TextStyle(fontSize: isFirst ? 20 : 16,
                    fontWeight: FontWeight.w900, color: color),
              )),
            ),
            const SizedBox(height: 6),
            Text(item.entry.username,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
            Text(label,
                style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Container(
              height: height,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6), topRight: Radius.circular(6)),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Center(child: Text('#${item.rank}',
                  style: TextStyle(fontSize: isFirst ? 22 : 18,
                      fontWeight: FontWeight.w900, color: color))),
            ),
          ]),
        );
      }).toList(),
    );
  }
}

// ── linha do ranking ─────────────────────────────────────────
class _LeaderRow extends StatelessWidget {
  final int rank;
  final _Entry entry;
  final bool isMe;
  final bool isCoin;
  final String coinName;

  const _LeaderRow({
    required this.rank,
    required this.entry,
    required this.isMe,
    required this.isCoin,
    required this.coinName,
  });

  @override
  Widget build(BuildContext context) {
    Color rankColor;
    if (rank == 1)      rankColor = _gold;
    else if (rank == 2) rankColor = const Color(0xFFC0C0C0);
    else if (rank == 3) rankColor = const Color(0xFFCD7F32);
    else                rankColor = _muted;

    // coluna direita: métrica principal
    final String mainValue;
    final String mainLabel;
    final String subLabel;

    if (isCoin) {
      final profit = entry.profit;
      mainValue = '${profit >= 0 ? '+' : ''}$profit';
      mainLabel = 'lucro';
      subLabel  = '${entry.coins} $coinName${entry.coins != 1 ? 's' : ''} atual';
    } else {
      final pts = entry.points;
      mainValue = pts == pts.truncate() ? pts.toInt().toString() : pts.toStringAsFixed(1);
      mainLabel = 'pontos';
      subLabel  = '${entry.wins} acerto${entry.wins != 1 ? 's' : ''} de ${entry.total} aposta${entry.total != 1 ? 's' : ''}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe ? _primary.withValues(alpha: 0.06) : _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe ? _primary.withValues(alpha: 0.4) : _border,
          width: isMe ? 1.5 : 1,
        ),
      ),
      child: Row(children: [
        SizedBox(width: 32,
          child: Text('#$rank',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
                  color: rankColor))),
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
              color: rankColor.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Center(child: Text(
            entry.username.isNotEmpty ? entry.username[0].toUpperCase() : '?',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                color: rankColor),
          )),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(entry.username,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              if (isMe) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('você',
                      style: TextStyle(fontSize: 9,
                          fontWeight: FontWeight.bold, color: _primary)),
                ),
              ],
            ]),
            Text(subLabel, style: const TextStyle(fontSize: 11, color: _muted)),
          ],
        )),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(mainValue,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                  color: isCoin
                      ? (entry.profit >= 0 ? _primary : Colors.red)
                      : (rank <= 3 ? rankColor : _primary))),
          Text(mainLabel, style: const TextStyle(fontSize: 9, color: _muted)),
        ]),
      ]),
    );
  }
}
