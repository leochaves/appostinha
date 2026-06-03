import 'bet_option.dart';

class Event {
  final String id;
  final String title;
  final String? description;
  final String createdBy;
  final String? categoryId;
  final String status;
  final String? winningOptionId;
  final DateTime createdAt;
  final List<BetOption> options;

  Event({
    required this.id,
    required this.title,
    this.description,
    required this.createdBy,
    this.categoryId,
    required this.status,
    this.winningOptionId,
    required this.createdAt,
    required this.options,
  });

  int get totalPredictions => options.fold(0, (sum, o) => sum + o.predictionCount);

  bool get isOpen => status == 'open';

  factory Event.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'] as List<dynamic>? ?? [];
    return Event(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      createdBy: json['created_by'] as String,
      categoryId: json['category_id'] as String?,
      status: json['status'] as String? ?? 'open',
      winningOptionId: json['winning_option_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      options: rawOptions
          .map((o) => BetOption.fromJson(o as Map<String, dynamic>))
          .toList(),
    );
  }
}
