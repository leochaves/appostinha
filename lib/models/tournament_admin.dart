class TournamentAdmin {
  final String tournamentId;
  final String userId;
  final String role;
  final String username;
  final DateTime addedAt;

  TournamentAdmin({
    required this.tournamentId,
    required this.userId,
    required this.role,
    required this.username,
    required this.addedAt,
  });

  bool get isOwner => role == 'owner';

  factory TournamentAdmin.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return TournamentAdmin(
      tournamentId: json['tournament_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      username: profile?['username'] as String? ?? 'Usuário',
      addedAt: DateTime.parse(json['added_at'] as String),
    );
  }
}
