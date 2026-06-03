class TournamentCategory {
  final String id;
  final String tournamentId;
  final String name;
  final String createdBy;
  final DateTime createdAt;

  TournamentCategory({
    required this.id,
    required this.tournamentId,
    required this.name,
    required this.createdBy,
    required this.createdAt,
  });

  factory TournamentCategory.fromJson(Map<String, dynamic> json) =>
      TournamentCategory(
        id: json['id'] as String,
        tournamentId: json['tournament_id'] as String,
        name: json['name'] as String,
        createdBy: json['created_by'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
