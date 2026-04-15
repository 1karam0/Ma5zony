enum RecommendationStatus { pending, approved, rejected }

class ManufacturingRecommendation {
  final String id;
  final String productId;
  final int suggestedQty;
  final double priority;
  final String reasoning;
  final double estimatedCost;
  final int estimatedTimeline; // days
  final bool cashConstraint;
  RecommendationStatus status;

  ManufacturingRecommendation({
    required this.id,
    required this.productId,
    required this.suggestedQty,
    required this.priority,
    required this.reasoning,
    required this.estimatedCost,
    required this.estimatedTimeline,
    this.cashConstraint = false,
    this.status = RecommendationStatus.pending,
  });

  factory ManufacturingRecommendation.fromFirestore(
      String id, Map<String, dynamic> data) {
    return ManufacturingRecommendation(
      id: id,
      productId: data['productId'] as String? ?? '',
      suggestedQty: (data['suggestedQty'] as num?)?.toInt() ?? 0,
      priority: (data['priority'] as num?)?.toDouble() ?? 0,
      reasoning: data['reasoning'] as String? ?? '',
      estimatedCost: (data['estimatedCost'] as num?)?.toDouble() ?? 0,
      estimatedTimeline: (data['estimatedTimeline'] as num?)?.toInt() ?? 0,
      cashConstraint: data['cashConstraint'] as bool? ?? false,
      status: RecommendationStatus.values.firstWhere(
        (e) => e.name == (data['status'] as String? ?? 'pending'),
        orElse: () => RecommendationStatus.pending,
      ),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'productId': productId,
      'suggestedQty': suggestedQty,
      'priority': priority,
      'reasoning': reasoning,
      'estimatedCost': estimatedCost,
      'estimatedTimeline': estimatedTimeline,
      'cashConstraint': cashConstraint,
      'status': status.name,
    };
  }
}
