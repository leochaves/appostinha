import 'package:flutter/material.dart';
import '../utils/error_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tournament_admin.dart';
import '../models/tournament.dart';

class AdminsScreen extends StatefulWidget {
  final Tournament tournament;

  const AdminsScreen({super.key, required this.tournament});

  @override
  State<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  List<TournamentAdmin> _admins = [];
  bool _loading = true;
  final _emailCtrl = TextEditingController();
  bool _adding = false;

  final _currentUserId = Supabase.instance.client.auth.currentUser?.id;

  bool get _isOwner => _admins.any(
      (a) => a.userId == _currentUserId && a.isOwner);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client
          .from('tournament_admins')
          .select('*, profiles!tournament_admins_user_id_fkey(username)')
          .eq('tournament_id', widget.tournament.id)
          .order('added_at', ascending: true);

      if (mounted) {
        setState(() {
          _admins = (data as List)
              .map((a) => TournamentAdmin.fromJson(a))
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ERRO load admins: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addAdmin() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() => _adding = true);
    try {
      final username = await Supabase.instance.client.rpc(
        'add_tournament_admin',
        params: {
          'p_tournament_id': widget.tournament.id,
          'p_email': email,
        },
      ) as String;
      _emailCtrl.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$username adicionado como admin!'),
          backgroundColor: const Color(0xFF00C851),
        ));
      }
    } catch (e) {
      debugPrint('ERRO [admins_screen.dart]: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeAdmin(TournamentAdmin admin) async {
    try {
      await Supabase.instance.client
          .from('tournament_admins')
          .delete()
          .eq('tournament_id', widget.tournament.id)
          .eq('user_id', admin.userId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${admin.username} removido'),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (e) {
      debugPrint('ERRO [admins_screen.dart]: $e');
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
      appBar: AppBar(
        title: const Text('Admins'),
        backgroundColor: const Color(0xFF0D1117),
      ),
      backgroundColor: const Color(0xFF0D1117),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00C851)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.tournament.name,
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  // Lista de admins
                  ..._admins.map((a) => _AdminTile(
                        admin: a,
                        isCurrentUser: a.userId == _currentUserId,
                        canRemove: _isOwner && !a.isOwner,
                        onRemove: () => _removeAdmin(a),
                      )),

                  // Adicionar admin (só owner)
                  if (_isOwner) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Adicionar admin',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF00C851)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: 'Email do usuário',
                              hintText: 'exemplo@email.com',
                              filled: true,
                              fillColor: const Color(0xFF161B22),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFF00C851)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _adding ? null : _addAdmin,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF00C851),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _adding
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black))
                              : const Text('Adicionar',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'O usuário precisa ter conta no app.',
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final TournamentAdmin admin;
  final bool isCurrentUser;
  final bool canRemove;
  final VoidCallback onRemove;

  const _AdminTile({
    required this.admin,
    required this.isCurrentUser,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: admin.isOwner
              ? const Color(0xFFFFD700).withValues(alpha: 0.3)
              : const Color(0xFF00C851).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: admin.isOwner
                  ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                  : const Color(0xFF00C851).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              admin.isOwner ? Icons.shield : Icons.admin_panel_settings,
              color: admin.isOwner
                  ? const Color(0xFFFFD700)
                  : const Color(0xFF00C851),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      admin.username,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Text(' (você)',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: admin.isOwner
                        ? const Color(0xFFFFD700).withValues(alpha: 0.1)
                        : const Color(0xFF00C851).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    admin.isOwner ? 'Owner' : 'Admin',
                    style: TextStyle(
                      fontSize: 10,
                      color: admin.isOwner
                          ? const Color(0xFFFFD700)
                          : const Color(0xFF00C851),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (canRemove)
            IconButton(
              icon: const Icon(Icons.person_remove_outlined,
                  color: Colors.red, size: 20),
              onPressed: onRemove,
              tooltip: 'Remover admin',
            ),
        ],
      ),
    );
  }
}
