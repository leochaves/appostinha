class Tournament {
  final String id;
  final String name;
  final String? description;
  final String createdBy;
  final String status;
  final DateTime createdAt;
  final String? votingCode;
  final String? slug;

  Tournament({
    required this.id,
    required this.name,
    this.description,
    required this.createdBy,
    required this.status,
    required this.createdAt,
    this.votingCode,
    this.slug,
  });

  bool get isActive => status == 'active';
  bool get hasVotingCode => votingCode != null && votingCode!.isNotEmpty;

  factory Tournament.fromJson(Map<String, dynamic> json) => Tournament(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        createdBy: json['created_by'] as String,
        status: json['status'] as String? ?? 'active',
        createdAt: DateTime.parse(json['created_at'] as String),
        votingCode: json['voting_code'] as String?,
        slug: json['slug'] as String?,
      );
}
