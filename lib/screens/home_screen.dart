import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tournament.dart';
import '../widgets/app_logo.dart'; // AppBarBrand + AppLogo
import 'create_tournament_screen.dart';

const _bg = Color(0xFF0D1117);
const _card = Color(0xFF161B22);
const _primary = Color(0xFF00C851);
const _gold = Color(0xFFD4A017);
const _border = Color(0xFF30363D);
const _muted = Color(0xFF8B949E);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Tournament> _tournaments = [];
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
          .from('tournaments')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _tournaments = (data as List).map((t) => Tournament.fromJson(t)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ERRO [home_screen.dart]: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _userInitials() {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return email.isEmpty ? '?' : email[0].toUpperCase();
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateTournamentScreen()),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _AppBar(userInitials: _userInitials()),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _primary))
                  : RefreshIndicator(
                      color: _primary,
                      onRefresh: _load,
                      child: _tournaments.isEmpty
                          ? _emptyState()
                          : _list(),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: _primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Torneio', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _emptyState() {
    return ListView(children: [
      const SizedBox(height: 80),
      const Center(
        child: Text(
          'Nenhum torneio ainda.\nCrie o primeiro!',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted),
        ),
      ),
    ]);
  }

  Widget _list() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 16 * 2 - 10) / 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _tournaments.map((t) => SizedBox(
              width: cardWidth,
              child: _TournamentCard(
                tournament: t,
                onTap: () => context.go('/torneio/${t.slug ?? t.id}'),
              ),
            )).toList(),
          ),
        );
      },
    );
  }
}

class _AppBar extends StatelessWidget {
  final String userInitials;
  const _AppBar({required this.userInitials});

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
          const AppBarBrand(logoSize: 36, fontSize: 22),
          const Spacer(),
          GestureDetector(
            onTap: () => context.go('/perfil'),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _border),
              ),
              child: Center(
                child: Text(
                  userInitials,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _gold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TournamentCard extends StatelessWidget {
  final Tournament tournament;
  final VoidCallback onTap;

  const _TournamentCard({required this.tournament, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: tournament.isActive
                ? _primary.withValues(alpha: 0.25)
                : _border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 6, height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: tournament.isActive ? _primary : _muted,
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                tournament.isActive ? 'ATIVO' : 'ENCERRADO',
                style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: tournament.isActive ? _primary : _muted,
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              tournament.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, height: 1.2),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (tournament.description != null && tournament.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                tournament.description!,
                style: const TextStyle(fontSize: 11, color: _muted, height: 1.4),
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
