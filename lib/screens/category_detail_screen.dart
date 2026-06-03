import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tournament.dart';
import '../models/category_model.dart';
import '../models/event.dart';
import 'create_event_screen.dart';

const _bg = Color(0xFF0D1117);
const _card = Color(0xFF161B22);
const _primary = Color(0xFF00C851);
const _gold = Color(0xFFD4A017);
const _border = Color(0xFF30363D);
const _muted = Color(0xFF8B949E);

class CategoryDetailScreen extends StatefulWidget {
  final TournamentCategory category;
  final Tournament tournament;
  final bool isAdmin;

  const CategoryDetailScreen({
    super.key,
    required this.category,
    required this.tournament,
    required this.isAdmin,
  });

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  List<Event> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client
          .from('events')
          .select('*, options!options_event_id_fkey(*)')
          .eq('category_id', widget.category.id)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _events = (data as List).map((e) => Event.fromJson(e)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ERRO load events: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreateEvent() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateEventScreen(categoryId: widget.category.id),
      ),
    );
    if (created == true) _load();
  }

  void _openEvent(Event event) {
    context.push('/evento/${event.id}');
  }

  @override
  Widget build(BuildContext context) {
    final open = _events.where((e) => e.isOpen).length;
    final resolved = _events.where((e) => e.status == 'resolved').length;
    final breadcrumb = '${widget.tournament.name} › ${widget.category.name}';

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _DetailAppBar(
              title: widget.category.name,
              subtitle: widget.tournament.name,
              onBack: () => Navigator.of(context).pop(),
            ),
            if (_events.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    _StatusChip(label: '$open abertos', color: _primary),
                    const SizedBox(width: 8),
                    _StatusChip(label: '$resolved resolvidos', color: _gold),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _primary))
                  : RefreshIndicator(
                      color: _primary,
                      onRefresh: _load,
                      child: _events.isEmpty
                          ? ListView(children: [
                              SizedBox(
                                height: 300,
                                child: Center(
                                  child: Text(
                                    widget.isAdmin
                                        ? 'Nenhum evento ainda.\nCrie o primeiro!'
                                        : 'Nenhum evento ainda.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: _muted),
                                  ),
                                ),
                              ),
                            ])
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              itemCount: _events.length,
                              itemBuilder: (_, i) => EventCard(
                                event: _events[i],
                                breadcrumb: breadcrumb,
                                onTap: () => _openEvent(_events[i]),
                              ),
                            ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: _openCreateEvent,
              backgroundColor: _primary,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add),
              label: const Text('Evento',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }
}

class _DetailAppBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  const _DetailAppBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
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
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: _muted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

// EventCard estilo Lovable: breadcrumb + título + barras de opções com fill
class EventCard extends StatelessWidget {
  final Event event;
  final String breadcrumb;
  final VoidCallback onTap;

  const EventCard({
    super.key,
    required this.event,
    required this.breadcrumb,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = event.totalPredictions;
    final isResolved = event.status == 'resolved';

    // ordena: lead (mais votos) primeiro
    final opts = [...event.options]
      ..sort((a, b) => b.predictionCount.compareTo(a.predictionCount));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isResolved
                ? _gold.withValues(alpha: 0.25)
                : event.isOpen
                    ? _primary.withValues(alpha: 0.2)
                    : _border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // breadcrumb + status
            Row(
              children: [
                Expanded(
                  child: Text(
                    breadcrumb.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: _muted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _statusBadge(event),
              ],
            ),
            const SizedBox(height: 8),
            // título
            Text(
              event.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (opts.isNotEmpty) ...[
              const SizedBox(height: 12),
              // barras de opção estilo Lovable
              ...opts.take(3).toList().asMap().entries.map((entry) {
                final i = entry.key;
                final o = entry.value;
                final isLead = i == 0;
                final isWinner = event.winningOptionId == o.id;
                final pct = total > 0 ? (o.predictionCount / total * 100).round() : 0;

                final fillColor = isWinner
                    ? _gold.withValues(alpha: 0.22)
                    : isLead
                        ? _primary.withValues(alpha: 0.18)
                        : _muted.withValues(alpha: 0.08);

                final labelColor = isWinner
                    ? _gold
                    : isLead
                        ? _primary
                        : _muted;

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        // background
                        Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: _bg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _border),
                          ),
                        ),
                        // fill
                        if (total > 0)
                          FractionallySizedBox(
                            widthFactor: pct / 100,
                            child: Container(
                              height: 36,
                              decoration: BoxDecoration(
                                color: fillColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        // label + %
                        SizedBox(
                          height: 36,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              children: [
                                if (isWinner)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(Icons.emoji_events, color: _gold, size: 12),
                                  ),
                                Expanded(
                                  child: Text(
                                    o.title,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  total > 0 ? '$pct%' : '—',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: labelColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              if (total > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '$total palpites',
                    style: const TextStyle(fontSize: 10, color: _muted),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(Event event) {
    Color color;
    String label;
    if (event.status == 'resolved') {
      color = _gold;
      label = 'Resolvido';
    } else if (event.isOpen) {
      color = _primary;
      label = 'Aberto';
    } else {
      color = _muted;
      label = 'Fechado';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
