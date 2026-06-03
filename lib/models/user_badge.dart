class UserBadge {
  final String badgeId;
  final String name;
  final String description;
  final String icon;
  final DateTime earnedAt;

  UserBadge({
    required this.badgeId,
    required this.name,
    required this.description,
    required this.icon,
    required this.earnedAt,
  });

  factory UserBadge.fromJson(Map<String, dynamic> json) {
    final badge = json['badges'] as Map<String, dynamic>? ?? {};
    return UserBadge(
      badgeId: json['badge_id'] as String,
      name: badge['name'] as String? ?? '',
      description: badge['description'] as String? ?? '',
      icon: badge['icon'] as String? ?? '🏅',
      earnedAt: DateTime.parse(json['earned_at'] as String),
    );
  }
}
