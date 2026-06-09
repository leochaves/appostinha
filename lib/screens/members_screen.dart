import 'package:flutter/material.dart';
import '../utils/error_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tournament.dart';

const _bg = Color(0xFF0D1117);
const _card = Color(0xFF161B22);
const _primary = Color(0xFF00C851);
const _border = Color(0xFF30363D);
const _muted = Color(0xFF8B949E);

class _Member {
  final String userId;
  final String username;
  final String status;
  final DateTime joinedAt;

  _Member({
    required this.userId,
    required this.username,
    required this.status,
    required this.joinedAt,
  });
}

class MembersScreen extends StatefulWidget {
  final Tournament tournament;

  const MembersScreen({super.key, required this.tournament});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<_Member> _pending = [];
  List<_Member> _approved = [];
  List<_Member> _rejected = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client
          .from('tournament_members')
          .select('*, profiles!tournament_members_user_id_fkey(username)')
          .eq('tournament_id', widget.tournament.id)
          .order('joined_at', ascending: true);

      final members = (data as List).map((m) {
        return _Member(
          userId: m['user_id'] as String,
          username: (m['profiles'] as Map)['username'] as String? ?? 'Usuário',
          status: m['status'] as String,
          joinedAt: DateTime.parse(m['joined_at'] as String),
        );
      }).toList();

      if (mounted) {
        setState(() {
          _pending  = members.where((m) => m.status == 'pending').toList();
          _approved = members.where((m) => m.status == 'approved').toList();
          _rejected = members.where((m) => m.status == 'rejected').toList();
          _loading  = false;
        });
      }
    } catch (e) {
      debugPrint('ERRO load members: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(String userId) async {
    try {
      await Supabase.instance.client.rpc('approve_member', params: {
        'p_tournament_id': widget.tournament.id,
        'p_user_id': userId,
      });
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Participante aprovado ✓'),
          backgroundColor: _primary,
        ));
      }
    } catch (e) {
      debugPrint('ERRO [members_screen.dart]: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _reject(String userId) async {
    try {
      await Supabase.instance.client.rpc('reject_member', params: {
        'p_tournament_id': widget.tournament.id,
        'p_user_id': userId,
      });
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Participante rejeitado'),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (e) {
      debugPrint('ERRO [members_screen.dart]: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Participantes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.tournament.name,
                style: const TextStyle(fontSize: 12, color: _muted)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _primary,
          labelColor: _primary,
          unselectedLabelColor: _muted,
          tabs: [
            Tab(text: 'Pendentes (${_pending.length})'),
            Tab(text: 'Aprovados (${_approved.length})'),
            Tab(text: 'Rejeitados (${_rejected.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _MemberList(
                  members: _pending,
                  emptyText: 'Nenhuma solicitação pendente.',
                  onApprove: _approve,
                  onReject: _reject,
                  showActions: true,
                ),
                _MemberList(
                  members: _approved,
                  emptyText: 'Nenhum participante aprovado ainda.',
                  showActions: false,
                ),
                _MemberList(
                  members: _rejected,
                  emptyText: 'Nenhum participante rejeitado.',
                  showActions: false,
                ),
              ],
            ),
    );
  }
}

class _MemberList extends StatelessWidget {
  final List<_Member> members;
  final String emptyText;
  final bool showActions;
  final void Function(String)? onApprove;
  final void Function(String)? onReject;

  const _MemberList({
    required this.members,
    required this.emptyText,
    required this.showActions,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Center(
        child: Text(emptyText, style: const TextStyle(color: _muted)),
      );
    }

    return RefreshIndicator(
      color: _primary,
      onRefresh: () async {},
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: members.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final m = members[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Row(children: [
              // avatar
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    m.username.isNotEmpty ? m.username[0].toUpperCase() : '?',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: _primary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.username,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(
                      'Solicitou ${_formatDate(m.joinedAt)}',
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
              if (showActions) ...[
                // Rejeitar
                GestureDetector(
                  onTap: () => onReject?.call(m.userId),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.close, color: Colors.red, size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                // Aprovar
                GestureDetector(
                  onTap: () => onApprove?.call(m.userId),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _primary.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.check, color: _primary, size: 18),
                  ),
                ),
              ] else
                _StatusChip(status: m.status),
            ]),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return 'há ${diff.inDays}d';
    if (diff.inHours > 0) return 'há ${diff.inHours}h';
    return 'há ${diff.inMinutes}min';
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == 'approved' ? _primary : Colors.red;
    final label = status == 'approved' ? 'Aprovado' : 'Rejeitado';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }
}
