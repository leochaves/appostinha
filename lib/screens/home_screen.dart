import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/event.dart';
import '../models/tournament.dart';
import 'create_tournament_screen.dart';

const _bg = Color(0xFF0D1117);
const _card = Color(0xFF161B22);
const _primary = Color(0xFF00C851);
const _gold = Color(0xFFD4A017);
const _border = Color(0xFF30363D);
const _muted = Color(0xFF8B949E);

class _EventWithBreadcrumb {
  final Event event;
  final String breadcrumb;
  final Tournament tournament;

  _EventWithBreadcrumb({
    required this.event,
    required this.breadcrumb,
    required this.tournament,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _filterIndex = 0;
  List<_EventWithBreadcrumb> _events = [];
  List<Tournament> _tournaments = [];
  bool _loading = true;

  static const _filters = ['Tudo', 'Abertos', 'Resolvidos'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // busca torneios, categorias e eventos em paralelo
      final tournamentsData = await Supabase.instance.client
          .from('tournaments')
          .select()
          .order('created_at', ascending: false);

      final tournaments = (tournamentsData as List)
          .map((t) => Tournament.fromJson(t))
          .toList();

      // busca eventos com opções e categoria
      final eventsData = await Supabase.instance.client
          .from('events')
          .select('*, options!options_event_id_fkey(*), categories!inner(id, name, tournament_id)')
          .order('created_at', ascending: false);

      final tournamentMap = {for (final t in tournaments) t.id: t};

      final events = <_EventWithBreadcrumb>[];
      for (final row in eventsData as List) {
        final cat = row['categories'] as Map<String, dynamic>;
        final tournamentId = cat['tournament_id'] as String;
        final tournament = tournamentMap[tournamentId];
        if (tournament == null) continue;
        final catName = cat['name'] as String;
        events.add(_EventWithBreadcrumb(
          event: Event.fromJson(row),
          breadcrumb: '${tournament.name} › $catName',
          tournament: tournament,
        ));
      }

      if (mounted) {
        setState(() {
          _tournaments = tournaments;
          _events = events;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ERRO load home: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_EventWithBreadcrumb> get _filtered {
    switch (_filterIndex) {
      case 1:
        return _events.where((e) => e.event.isOpen).toList();
      case 2:
        return _events.where((e) => e.event.status == 'resolved').toList();
      default:
        return _events;
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateTournamentScreen()),
    );
    if (created == true) _load();
  }

  void _openEvent(_EventWithBreadcrumb item) {
    context.push('/evento/${item.event.id}');
  }

  void _openTournaments() async {
    if (_tournaments.isEmpty) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TournamentsSheet(
        tournaments: _tournaments,
        currentUserId: userId,
        onTap: (t) {
          Navigator.pop(context);
          context.push('/torneio/${t.id}');
        },
        onDelete: (t) {
          Navigator.pop(context);
          _deleteTournament(t);
        },
      ),
    );
  }

  void _deleteTournament(Tournament t) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Deletar torneio'),
        content: Text('Deletar "${t.name}" e tudo dentro dele?'),
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
                    .from('tournaments')
                    .delete()
                    .eq('id', t.id);
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

  String _userInitials() {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return email.isEmpty ? '?' : email[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _EventsTab(
        events: _filtered,
        allEvents: _events,
        loading: _loading,
        filterIndex: _filterIndex,
        filters: _filters,
        onFilterChanged: (i) => setState(() => _filterIndex = i),
        onRefresh: _load,
        onTap: _openEvent,
        userInitials: _userInitials(),
        onTournaments: _openTournaments,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: _primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Torneio',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _EventsTab extends StatelessWidget {
  final List<_EventWithBreadcrumb> events;
  final List<_EventWithBreadcrumb> allEvents;
  final bool loading;
  final int filterIndex;
  final List<String> filters;
  final void Function(int) onFilterChanged;
  final Future<void> Function() onRefresh;
  final void Function(_EventWithBreadcrumb) onTap;
  final String userInitials;
  final VoidCallback onTournaments;

  const _EventsTab({
    required this.events,
    required this.allEvents,
    required this.loading,
    required this.filterIndex,
    required this.filters,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onTap,
    required this.userInitials,
    required this.onTournaments,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _AppBar(userInitials: userInitials, onTournaments: onTournaments),
          _FilterRow(
              selected: filterIndex, filters: filters, onTap: onFilterChanged),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: _primary))
                : RefreshIndicator(
                    color: _primary,
                    onRefresh: onRefresh,
                    child: events.isEmpty ? _emptyState() : _list(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return ListView(children: [
      const SizedBox(height: 80),
      const Center(
        child: Text(
          'Nenhum evento ainda.\nCrie um torneio e adicione eventos!',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted),
        ),
      ),
    ]);
  }

  Widget _list() {
    final featured = events.first;
    final rest = events.skip(1).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // Hero: primeiro evento em destaque
        _HeroEventCard(item: featured, onTap: () => onTap(featured)),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _SectionLabel(label: 'Próximos Eventos'),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.9,
            ),
            itemCount: rest.length,
            itemBuilder: (_, i) => _GridEventCard(
              item: rest[i],
              onTap: () => onTap(rest[i]),
            ),
          ),
        ],
      ],
    );
  }
}

// AppBar
class _AppBar extends StatelessWidget {
  final String userInitials;
  final VoidCallback onTournaments;

  const _AppBar({required this.userInitials, required this.onTournaments});

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
          const Text(
            'APOSTINHA',
            style: TextStyle(
              color: _primary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onTournaments,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events_outlined, color: _muted, size: 15),
                  SizedBox(width: 5),
                  Text('Torneios',
                      style: TextStyle(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Center(
              child: Text(
                userInitials,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: _gold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Filter chips
class _FilterRow extends StatelessWidget {
  final int selected;
  final List<String> filters;
  final void Function(int) onTap;

  const _FilterRow(
      {required this.selected, required this.filters, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: filters.length,
        itemBuilder: (_, i) {
          final active = i == selected;
          return GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? _primary : _card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? _primary : _border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (filters[i] == 'Abertos') ...[
                    Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    filters[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: active ? Colors.black : _muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// Hero card — destaque com borda dourada
class _HeroEventCard extends StatelessWidget {
  final _EventWithBreadcrumb item;
  final VoidCallback onTap;

  const _HeroEventCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final event = item.event;
    final total = event.totalPredictions;
    final opts = [...event.options]
      ..sort((a, b) => b.predictionCount.compareTo(a.predictionCount));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _gold.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
                color: _gold.withValues(alpha: 0.05),
                blurRadius: 20,
                spreadRadius: 2),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  item.breadcrumb.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: _primary),
                ),
                const Spacer(),
                Text(
                  'EM DESTAQUE',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: _gold.withValues(alpha: 0.8)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              event.title,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                  letterSpacing: -0.5),
            ),
            const SizedBox(height: 16),
            // barras estilo Lovable
            ...opts.take(2).toList().asMap().entries.map((entry) {
              final isLead = entry.key == 0;
              final o = entry.value;
              final pct =
                  total > 0 ? o.predictionCount / total : (isLead ? 0.5 : 0.5);
              final pctLabel =
                  total > 0 ? '${(pct * 100).round()}%' : '—';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(o.title,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text(pctLabel,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isLead ? _primary : _muted)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Stack(children: [
                        Container(height: 8, color: _bg),
                        FractionallySizedBox(
                          widthFactor: pct.clamp(0.0, 1.0),
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: isLead ? _primary : _muted.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('$total palpites',
                    style: const TextStyle(fontSize: 11, color: _muted)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _gold,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Apostar Agora',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Colors.black)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Grid card — estilo Lovable EventCard
class _GridEventCard extends StatelessWidget {
  final _EventWithBreadcrumb item;
  final VoidCallback onTap;

  const _GridEventCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final event = item.event;
    final total = event.totalPredictions;
    final opts = [...event.options]
      ..sort((a, b) => b.predictionCount.compareTo(a.predictionCount));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: event.isOpen
                ? _border
                : event.status == 'resolved'
                    ? _gold.withValues(alpha: 0.2)
                    : _border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.breadcrumb.toUpperCase(),
              style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: _muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                event.title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, height: 1.3),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            // barras compactas
            ...opts.take(2).toList().asMap().entries.map((entry) {
              final isLead = entry.key == 0;
              final isWinner = event.winningOptionId == opts[entry.key].id;
              final o = entry.value;
              final pct = total > 0 ? (o.predictionCount / total * 100).round() : 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 5),
                height: 28,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(children: [
                    Container(
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _border),
                      ),
                    ),
                    if (total > 0)
                      FractionallySizedBox(
                        widthFactor: (pct / 100).clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isWinner
                                ? _gold.withValues(alpha: 0.25)
                                : isLead
                                    ? _primary.withValues(alpha: 0.2)
                                    : _muted.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(o.title,
                                style: const TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis),
                          ),
                          Text(
                            total > 0 ? '$pct%' : '—',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isWinner
                                  ? _gold
                                  : isLead
                                      ? _primary
                                      : _muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
              );
            }),
          ],
        ),
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


// Sheet de torneios
class _TournamentsSheet extends StatelessWidget {
  final List<Tournament> tournaments;
  final String? currentUserId;
  final void Function(Tournament) onTap;
  final void Function(Tournament) onDelete;

  const _TournamentsSheet({
    required this.tournaments,
    required this.currentUserId,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        const Text('Torneios',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...tournaments.map((t) {
          final isOwner = currentUserId != null && t.createdBy == currentUserId;
          return ListTile(
            leading: Icon(Icons.emoji_events,
                color: t.isActive ? _primary : _muted),
            title: Text(t.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(t.isActive ? 'Ativo' : 'Encerrado',
                style: TextStyle(
                    color: t.isActive ? _primary : _muted, fontSize: 12)),
            onTap: () => onTap(t),
            trailing: isOwner
                ? IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 20),
                    onPressed: () => onDelete(t),
                  )
                : null,
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }
}
