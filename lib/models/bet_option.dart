class BetOption {
  final String id;
  final String eventId;
  final String title;
  final int predictionCount;
  final int coinPool;

  BetOption({
    required this.id,
    required this.eventId,
    required this.title,
    required this.predictionCount,
    this.coinPool = 0,
  });

  factory BetOption.fromJson(Map<String, dynamic> json) => BetOption(
        id: json['id'] as String,
        eventId: json['event_id'] as String,
        title: json['title'] as String,
        predictionCount: (json['prediction_count'] ?? json['total_pool'] ?? 0) as int,
        coinPool: (json['coin_pool'] ?? 0) as int,
      );

  double odds(int totalPredictions) {
    if (predictionCount == 0 || totalPredictions == 0) return 0;
    return totalPredictions / predictionCount;
  }

  double percentage(int totalPredictions) {
    if (predictionCount == 0 || totalPredictions == 0) return 0;
    return predictionCount / totalPredictions;
  }
}
