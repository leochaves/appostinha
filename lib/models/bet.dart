class Bet {
  final String id;
  final String userId;
  final String eventId;
  final String optionId;
  final String status;
  final DateTime createdAt;
  final String? eventTitle;
  final String? optionTitle;

  Bet({
    required this.id,
    required this.userId,
    required this.eventId,
    required this.optionId,
    required this.status,
    required this.createdAt,
    this.eventTitle,
    this.optionTitle,
  });

  factory Bet.fromJson(Map<String, dynamic> json) => Bet(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        eventId: json['event_id'] as String,
        optionId: json['option_id'] as String,
        status: json['status'] as String? ?? 'pending',
        createdAt: DateTime.parse(json['created_at'] as String),
        eventTitle: json['events'] != null
            ? (json['events'] as Map)['title'] as String?
            : null,
        optionTitle: json['options'] != null
            ? (json['options'] as Map)['title'] as String?
            : null,
      );
}
