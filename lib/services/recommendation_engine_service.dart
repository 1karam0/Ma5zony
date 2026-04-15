import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/models/cash_flow_snapshot.dart';
import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/manufacturing_recommendation.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/raw_material.dart';

/// Client-side recommendation engine that mirrors the backend logic.
/// Used for instant previews without a backend round-trip.
class RecommendationEngineService {
  /// Generate manufacturing recommendations from current domain state.
  List<ManufacturingRecommendation> generate({
    required List<Product> products,
    required List<BillOfMaterials> boms,
    required List<RawMaterial> rawMaterials,
    required Map<String, List<DomainDemandRecord>> demandByProduct,
    CashFlowSnapshot? latestCashFlow,
  }) {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final rmMap = {for (final rm in rawMaterials) rm.id: rm};

    double remainingBudget = latestCashFlow != null
        ? latestCashFlow.remainingBudget
        : double.infinity;

    final scored = <_ScoredProduct>[];

    for (final product in products) {
      final records = demandByProduct[product.id] ?? [];
      final recentDemand = records
          .where((d) => d.periodStart.isAfter(thirtyDaysAgo))
          .toList();
      final velocity =
          recentDemand.fold<int>(0, (sum, d) => sum + d.quantity);

      final dailyRate = velocity / 30.0;
      final effectiveRate = dailyRate > 0 ? dailyRate : 0.1;
      final daysOfStock = product.currentStock / effectiveRate;
      final urgency = (1 - daysOfStock / 60).clamp(0.0, 1.0);

      // Skip if stock is fine
      if (product.currentStock > 0 && urgency <= 0) continue;

      // BOM cost
      final bom = boms.where((b) => b.finalProductId == product.id).firstOrNull;
      double unitCost = 0;
      if (bom != null) {
        for (final mat in bom.materials) {
          final rm = rmMap[mat.rawMaterialId];
          unitCost += (rm?.unitCost ?? 0) * mat.quantityPerUnit;
        }
      }

      final targetStock = (effectiveRate * 30).ceil();
      final suggestedQty =
          (targetStock - product.currentStock).clamp(1, 999999);

      scored.add(_ScoredProduct(
        product: product,
        velocity: velocity,
        urgency: urgency,
        unitCost: unitCost,
        suggestedQty: suggestedQty,
      ));
    }

    scored.sort((a, b) => b.urgency.compareTo(a.urgency));

    final recs = <ManufacturingRecommendation>[];
    var counter = 0;

    for (final item in scored) {
      final totalCost = item.unitCost * item.suggestedQty;
      final cashConstrained = totalCost > remainingBudget;

      recs.add(ManufacturingRecommendation(
        id: 'rec-${DateTime.now().millisecondsSinceEpoch}-${counter++}',
        productId: item.product.id,
        suggestedQty: item.suggestedQty,
        priority: (item.urgency * 100).round().toDouble(),
        reasoning: _buildReasoning(
            item.product, item.velocity, item.urgency, cashConstrained),
        estimatedCost: totalCost,
        estimatedTimeline: 14,
        cashConstraint: cashConstrained,
      ));

      if (!cashConstrained) {
        remainingBudget -= totalCost;
      }
    }

    return recs;
  }

  String _buildReasoning(
    Product product,
    int velocity,
    double urgency,
    bool cashConstrained,
  ) {
    final parts = <String>[];
    if (product.currentStock <= 0) {
      parts.add('Stock is at zero.');
    }
    if (velocity > 0) {
      final daysLeft = (product.currentStock / (velocity / 30)).round();
      parts.add(
          'At current sales velocity ($velocity units/30d), stock covers ~$daysLeft days.');
    } else {
      parts.add('No recent sales data available.');
    }
    if (urgency >= 0.8) {
      parts.add('HIGH PRIORITY — stock critically low.');
    }
    if (cashConstrained) {
      parts.add('⚠ Insufficient cash to fully fund this production run.');
    }
    return parts.join(' ');
  }
}

class _ScoredProduct {
  final Product product;
  final int velocity;
  final double urgency;
  final double unitCost;
  final int suggestedQty;

  _ScoredProduct({
    required this.product,
    required this.velocity,
    required this.urgency,
    required this.unitCost,
    required this.suggestedQty,
  });
}
