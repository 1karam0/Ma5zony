import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/replenishment_recommendation.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/services/forecasting_service.dart';
import 'package:ma5zony/services/inventory_policy_service.dart';
import 'package:ma5zony/services/settings_service.dart';

/// Builds replenishment recommendations from products, demand history and
/// supplier metadata using [ForecastingService] and [InventoryPolicyService].
class ReplenishmentService {
  final ForecastingService _forecastingService;
  final InventoryPolicyService _policyService;

  ReplenishmentService({
    ForecastingService? forecastingService,
    InventoryPolicyService? policyService,
  }) : _forecastingService = forecastingService ?? ForecastingService(),
       _policyService = policyService ?? InventoryPolicyService();

  /// Generates [ReplenishmentRecommendation] objects for products whose
  /// current stock is at or below the computed reorder point.
  ///
  /// Uses a default supplier when none matches (leadTime = 7 days).
  /// Maps a service-level percentage (e.g. 95) to its Z-score.
  static double _serviceLevelToZ(double serviceLevelPercent) {
    if (serviceLevelPercent >= 99) return 2.33;
    if (serviceLevelPercent >= 97.5) return 1.96;
    if (serviceLevelPercent >= 95) return 1.65;
    if (serviceLevelPercent >= 90) return 1.28;
    if (serviceLevelPercent >= 85) return 1.04;
    if (serviceLevelPercent >= 80) return 0.84;
    return 0.67;
  }

  List<ReplenishmentRecommendation> buildRecommendations({
    required List<Product> products,
    required Map<String, List<DomainDemandRecord>> demandByProduct,
    required Map<String, Supplier> suppliers,
    UserSettings? settings,
  }) {
    final recommendations = <ReplenishmentRecommendation>[];

    for (final product in products) {
      final records = demandByProduct[product.id] ?? [];
      if (records.isEmpty) continue;

      // Sort by period ascending
      records.sort((a, b) => a.periodStart.compareTo(b.periodStart));
      final demandSeries = records.map((r) => r.quantity.toDouble()).toList();

      final supplier =
          (product.supplierId != null &&
              suppliers.containsKey(product.supplierId))
          ? suppliers[product.supplierId]!
          : Supplier(
              id: '_default',
              name: 'Default',
              contactEmail: '',
              typicalLeadTimeDays: 7,
            );

      final policy = _policyService.buildPolicy(
        product: product,
        demandSeries: demandSeries,
        supplier: supplier,
        serviceLevelZ: settings != null
            ? _serviceLevelToZ(settings.serviceLevelTarget)
            : 1.65,
      );

      // Only include products at or below ROP
      if (product.currentStock <= policy.reorderPoint) {
        // Resolve effective lead time: product-level overrides supplier default
        final effectiveLeadTimeDays = product.leadTimeDays > 0
            ? product.leadTimeDays
            : supplier.typicalLeadTimeDays;

        // Forecast next period demand using SMA(3)
        final nextForecast = _forecastingService
            .simpleMovingAverage(demandSeries, 3)
            .toInt();

        final suggestedQty = policy.eoq.ceil().clamp(1, 99999);

        // Compute order date: if stock covers demand during lead time we can
        // wait; otherwise order immediately. Days of stock remaining =
        // currentStock / (avgDailyDemand). Order must arrive by that day.
        final avgMonthlyDemand = demandSeries.reduce((a, b) => a + b) /
            demandSeries.length;
        final avgDailyDemand = avgMonthlyDemand / 30.0;
        final daysOfStockLeft = avgDailyDemand > 0
            ? (product.currentStock / avgDailyDemand).floor()
            : 0;
        final latestOrderDay = daysOfStockLeft - effectiveLeadTimeDays;
        final orderInDays = latestOrderDay > 1 ? latestOrderDay : 1;

        recommendations.add(
          ReplenishmentRecommendation(
            productId: product.id,
            productName: product.name,
            sku: product.sku,
            currentStock: product.currentStock,
            forecastNextPeriod: nextForecast,
            reorderPoint: policy.reorderPoint,
            suggestedOrderQty: suggestedQty,
            recommendedOrderDate: DateTime.now().add(
              Duration(days: orderInDays),
            ),
          ),
        );
      }
    }

    // Sort: critical first (currentStock == 0), then by lowest stock
    recommendations.sort((a, b) {
      if (a.currentStock == 0 && b.currentStock != 0) return -1;
      if (b.currentStock == 0 && a.currentStock != 0) return 1;
      return a.currentStock.compareTo(b.currentStock);
    });

    return recommendations;
  }
}
