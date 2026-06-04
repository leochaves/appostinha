import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';
import '../models/bet.dart';
import '../models/user_badge.dart';
import 'auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _profile;
  List<Bet> _bets = [];
  List<UserBadge> _badges = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/auth'));
      return;
    }
    try {
      final results = await Future.wait([
        Supabase.instance.client.from('profiles').select().eq('id', userId).single(),
        Supabase.instance.client
            .from('bets')
            .select('*, events(title), options(title)')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(50),
        Supabase.instance.client
            .from('user_badges')
            .select('*, badges(*)')
            .eq('user_id', userId)
            .order('earned_at', ascending: true),
      ]);

      if (mounted) {
        setState(() {
          _profile = Profile.fromJson(results[0] as Map<String, dynamic>);
          _bets = (results[1] as List).map((b) => Bet.fromJson(b)).toList();
          _badges = (results[2] as List).map((b) => UserBadge.fromJson(b)).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00C851)));
    }

    final won = _bets.where((b) => b.status == 'won').length;
    final lost = _bets.where((b) => b.status == 'lost').length;
    final pending = _bets.where((b) => b.status == 'pending').length;
    final total = won + lost;
    final hitRate = total > 0 ? (won / total * 100).round() : 0;

    return RefreshIndicator(
      color: const Color(0xFF00C851),
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Perfil',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.grey),
                  onPressed: _logout,
                  tooltip: 'Sair',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Card do usuário
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF003D1C), Color(0xFF161B22)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00C851).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_circle, size: 52, color: Color(0xFF00C851)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_profile?.username ?? 'Usuário',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          total > 0 ? '$hitRate% de acerto' : 'Sem palpites ainda',
                          style: TextStyle(
                            color: total > 0
                                ? hitRate >= 60
                                    ? const Color(0xFF00C851)
                                    : Colors.orange
                                : Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Stats
            Row(
              children: [
                _StatCard(label: 'Acertos', value: won, color: const Color(0xFF00C851)),
                const SizedBox(width: 10),
                _StatCard(label: 'Erros', value: lost, color: Colors.redAccent),
                const SizedBox(width: 10),
                _StatCard(label: 'Abertos', value: pending, color: const Color(0xFFFFD700)),
              ],
            ),

            const SizedBox(height: 24),

            // Badges
            const Text('Conquistas',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            _badges.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Faça palpites e acerte para ganhar conquistas!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.9,
                    children: _badges.map((b) => _BadgeCard(badge: b)).toList(),
                  ),

            const SizedBox(height: 24),

            // Histórico
            const Text('Palpites recentes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            if (_bets.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Nenhum palpite ainda',
                      style: TextStyle(color: Colors.grey[500])),
                ),
              )
            else
              ..._bets.take(20).map((b) => _BetTile(bet: b)),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(value.toString(),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final UserBadge badge;

  const _BadgeCard({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(badge.icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 6),
          Text(
            badge.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Color(0xFFFFD700),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            badge.description,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 9),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _BetTile extends StatelessWidget {
  final Bet bet;

  const _BetTile({required this.bet});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    switch (bet.status) {
      case 'won':
        color = const Color(0xFF00C851);
        label = 'Acertou!';
        icon = Icons.check_circle_outline;
      case 'lost':
        color = Colors.redAccent;
        label = 'Errou';
        icon = Icons.cancel_outlined;
      default:
        color = const Color(0xFFFFD700);
        label = 'Aguardando';
        icon = Icons.schedule;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bet.eventTitle ?? 'Evento',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(bet.optionTitle ?? '',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              ],
            ),
          ),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}
