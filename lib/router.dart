import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/tournament_detail_screen.dart';
import 'screens/event_detail_screen.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/update_password_screen.dart';
import 'models/tournament.dart';
import 'models/event.dart';
import 'widgets/app_shell.dart';

// ── Notifier de auth para redirect ───────────────────────────
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }

  bool get isLoggedIn =>
      Supabase.instance.client.auth.currentSession != null;
}

final authNotifier = _AuthNotifier();

// ── Splash simples ────────────────────────────────────────────
class _SplashPage extends StatelessWidget {
  const _SplashPage();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Color(0xFF0D1117),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('APPostinha',
                  style: TextStyle(
                      color: Color(0xFF00C851),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2)),
              SizedBox(height: 24),
              CircularProgressIndicator(
                  color: Color(0xFF00C851), strokeWidth: 2),
            ],
          ),
        ),
      );
}

// ── Carrega torneio por ID ────────────────────────────────────
class TournamentPage extends StatefulWidget {
  final String tournamentId;
  const TournamentPage({super.key, required this.tournamentId});

  @override
  State<TournamentPage> createState() => _TournamentPageState();
}

class _TournamentPageState extends State<TournamentPage> {
  Tournament? _tournament;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // tenta buscar por slug primeiro, depois por id
      List data = await Supabase.instance.client
          .from('tournaments')
          .select()
          .eq('slug', widget.tournamentId)
          .limit(1);
      if (data.isEmpty) {
        data = await Supabase.instance.client
            .from('tournaments')
            .select()
            .eq('id', widget.tournamentId)
            .limit(1);
      }
      if (data.isEmpty) throw Exception('not found');
      if (mounted) setState(() => _tournament = Tournament.fromJson(data.first));
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Torneio não encontrado',
                style: TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Voltar ao início'),
            ),
          ]),
        ),
      );
    }
    if (_tournament == null) return const _SplashPage();
    return TournamentDetailScreen(tournament: _tournament!);
  }
}

// ── Carrega leaderboard por tournamentId ─────────────────────
class LeaderboardPage extends StatefulWidget {
  final String tournamentId;
  const LeaderboardPage({super.key, required this.tournamentId});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  Tournament? _tournament;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      List data = await Supabase.instance.client
          .from('tournaments')
          .select()
          .eq('slug', widget.tournamentId)
          .limit(1);
      if (data.isEmpty) {
        data = await Supabase.instance.client
            .from('tournaments')
            .select()
            .eq('id', widget.tournamentId)
            .limit(1);
      }
      if (data.isEmpty) throw Exception('not found');
      if (mounted) setState(() => _tournament = Tournament.fromJson(data.first));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_tournament == null) return const _SplashPage();
    return LeaderboardScreen(tournament: _tournament!);
  }
}

// ── Carrega evento por ID ─────────────────────────────────────
class EventPage extends StatefulWidget {
  final String eventId;
  const EventPage({super.key, required this.eventId});

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  Event? _event;
  String? _breadcrumb;
  String? _tournamentId;
  String? _votingCode;
  bool _isAdmin = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;

      final data = await Supabase.instance.client
          .from('events')
          .select('*, options!options_event_id_fkey(*), categories!inner(name, tournament_id, tournaments!inner(name, created_by, voting_code))')
          .eq('id', widget.eventId)
          .single();

      final event = Event.fromJson(data);
      final cat = data['categories'] as Map;
      final tournament = cat['tournaments'] as Map;
      final breadcrumb = '${tournament['name']} › ${cat['name']}';
      final tournamentId = cat['tournament_id'] as String;
      final votingCode = tournament['voting_code'] as String?;
      final isAdmin = userId != null && tournament['created_by'] == userId;

      // checa tournament_admins também
      bool adminFromTable = false;
      if (userId != null && !isAdmin) {
        try {
          final a = await Supabase.instance.client
              .from('tournament_admins')
              .select('role')
              .eq('tournament_id', tournamentId)
              .eq('user_id', userId)
              .maybeSingle();
          adminFromTable = a != null;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _event = event;
          _breadcrumb = breadcrumb;
          _isAdmin = isAdmin || adminFromTable;
          _tournamentId = tournamentId;
          _votingCode = votingCode;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Evento não encontrado',
                style: TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Voltar ao início'),
            ),
          ]),
        ),
      );
    }
    if (_event == null) return const _SplashPage();
    return EventDetailScreen(
        event: _event!,
        isAdmin: _isAdmin,
        breadcrumb: _breadcrumb,
        tournamentId: _tournamentId,
        votingCode: _votingCode);
  }
}

// ── Router ────────────────────────────────────────────────────
final router = GoRouter(
  refreshListenable: authNotifier,
  initialLocation: '/',
  redirect: (context, state) {
    final loggedIn = authNotifier.isLoggedIn;
    // só redireciona /auth → / se já logado
    if (loggedIn && state.matchedLocation == '/auth') return '/';
    return null;
  },
  routes: [
    // Rotas sem shell (sem bottom bar)
    GoRoute(
      path: '/auth',
      builder: (_, state) => AuthScreen(
        redirectTo: state.uri.queryParameters['redirect'],
      ),
    ),
    GoRoute(
      path: '/recuperar-senha',
      builder: (_, __) => const UpdatePasswordScreen(),
    ),
    GoRoute(
      path: '/evento/:id',
      builder: (_, state) =>
          EventPage(eventId: state.pathParameters['id']!),
    ),
    // Shell com bottom bar
    ShellRoute(
      builder: (_, __, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const HomeScreen(),
        ),
        GoRoute(
          path: '/perfil',
          builder: (_, __) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/torneio/:id',
          builder: (_, state) =>
              TournamentPage(tournamentId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/torneio/:id/leaderboard',
          builder: (_, state) =>
              LeaderboardPage(tournamentId: state.pathParameters['id']!),
        ),
      ],
    ),
  ],
);
