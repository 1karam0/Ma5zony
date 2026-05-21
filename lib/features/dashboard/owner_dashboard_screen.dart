import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/production_order.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

/// Dashboard shown only to users with the **SME Owner** role.
///
/// Includes financial KPIs (inventory value, COGS, holding costs, open order
/// cost), operational KPIs, revenue-vs-cost chart, inventory value chart,
/// cash-flow projection, and breakdown tables.
class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  bool _showBanner = true;
  bool _showChecklist = true;

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Monthly COGS estimate = Σ(demand qty last 30 days × unit cost).
  double _monthlyCOGS(AppState state) {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    double cogs = 0;
    for (final entry in state.demandByProduct.entries) {
      final product = state.products.where((p) => p.id == entry.key).firstOrNull;
      if (product == null) continue;
      for (final d in entry.value) {
        if (d.periodStart.isAfter(thirtyDaysAgo)) {
          cogs += d.quantity * product.unitCost;
        }
      }
    }
    return cogs;
  }

  /// Estimated monthly holding cost = inventory value × annual holding rate / 12.
  double _monthlyHoldingCost(AppState state) {
    final annualHoldingRate = state.settings.holdingRate;
    return state.totalStockValue * annualHoldingRate / 12;
  }

  /// Open order cost = Σ(suggestedQty × unitCost) for all open recommendations.
  double _openOrderCost(AppState state) {
    double total = 0;
    for (final rec in state.recommendations) {
      final product =
          state.products.where((p) => p.id == rec.productId).firstOrNull;
      if (product != null) {
        total += rec.suggestedOrderQty * product.unitCost;
      }
    }
    return total;
  }

  /// Total units in stock.
  int _totalUnits(AppState state) =>
      state.products.fold<int>(0, (s, p) => s + p.currentStock);

  /// Products sorted by monthly projected spend (forecast × unitCost) desc.
  List<_ProductSpend> _topExpenseProducts(AppState state) {
    final result = <_ProductSpend>[];
    for (final p in state.products) {
      final rec =
          state.recommendations.where((r) => r.productId == p.id).firstOrNull;
      final forecast = rec?.forecastNextPeriod ?? 0;
      result.add(_ProductSpend(
        name: p.name,
        sku: p.sku,
        monthlyForecast: forecast,
        unitCost: p.unitCost,
        monthlySpend: forecast * p.unitCost,
      ));
    }
    result.sort((a, b) => b.monthlySpend.compareTo(a.monthlySpend));
    return result;
  }

  /// Supplier cost breakdown.
  List<_SupplierCost> _supplierCostBreakdown(AppState state) {
    final map = <String, _SupplierCost>{};
    for (final p in state.products) {
      final supplierId = p.supplierId;
      if (supplierId == null) continue;
      final supplier =
          state.suppliers.where((s) => s.id == supplierId).firstOrNull;
      final name = supplier?.name ?? 'Unknown';
      final leadTime = supplier?.typicalLeadTimeDays ?? 0;
      final rec =
          state.recommendations.where((r) => r.productId == p.id).firstOrNull;
      final spend = (rec?.forecastNextPeriod ?? 0) * p.unitCost;

      if (map.containsKey(supplierId)) {
        map[supplierId] = _SupplierCost(
          name: name,
          productCount: map[supplierId]!.productCount + 1,
          avgLeadTime: ((map[supplierId]!.avgLeadTime *
                      map[supplierId]!.productCount) +
                  leadTime) /
              (map[supplierId]!.productCount + 1),
          totalMonthlySpend: map[supplierId]!.totalMonthlySpend + spend,
        );
      } else {
        map[supplierId] = _SupplierCost(
          name: name,
          productCount: 1,
          avgLeadTime: leadTime.toDouble(),
          totalMonthlySpend: spend,
        );
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => b.totalMonthlySpend.compareTo(a.totalMonthlySpend));
    return list;
  }

  /// Cash-flow projection for next 3 months (simplified: forecast × unitCost).
  List<double> _cashFlowProjection(AppState state) {
    // Base monthly projected spend from all products
    double baseSpend = 0;
    for (final p in state.products) {
      final rec =
          state.recommendations.where((r) => r.productId == p.id).firstOrNull;
      baseSpend += (rec?.forecastNextPeriod ?? 0) * p.unitCost;
    }
    // 3-month projection: month 1 = base, month 2 & 3 use same estimate
    return [baseSpend, baseSpend, baseSpend];
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final cogs = _monthlyCOGS(state);
    final holdingCost = _monthlyHoldingCost(state);
    final openOrderCost = _openOrderCost(state);
    final topProducts = _topExpenseProducts(state);
    final supplierCosts = _supplierCostBreakdown(state);
    final cashFlow = _cashFlowProjection(state);
    final totalSpend = topProducts.fold<double>(0, (s, p) => s + p.monthlySpend);

    final user = state.currentUser;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Shopify banner ───────────────────────────────────────────
          if (_showBanner && state.shopifyConnection?.isConnected != true)
            _buildShopifyBanner(),

          // ── Greeting ─────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$greeting, ${user?.name.split(' ').first ?? 'Owner'}',
                      style: AppTextStyles.h1),
                  Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                      style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Critical stock urgency banner + table ────────────────────
          if (state.hasUrgentStockAlerts) _buildCriticalStockSection(state),

          // ── Secondary: open recommendations ──────────────────────────
          if (state.openRecommendations > 0) _buildOpenRecsCard(state),

          // ── Getting Started checklist ────────────────────────────────
          if (_showChecklist) _buildOnboardingChecklist(state),

          // ── Hero metric card ─────────────────────────────────────────
          _buildHeroCard(state, cogs, holdingCost, openOrderCost),

          const SizedBox(height: 24),

          // ── Operational + Manufacturing side by side ─────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              final pendingMaterialOrders = state.rawMaterialOrders
                  .where((o) => o.status != 'completed')
                  .length;
              final activeProductionOrders = state.productionOrders
                  .where((o) =>
                      o.status != ProductionOrderStatus.completed &&
                      o.status != ProductionOrderStatus.draft)
                  .length;
              final budgetRemaining =
                  state.latestCashFlow?.totalAvailable ?? 0;
              final allocatedBudget =
                  state.latestCashFlow?.allocatedToProduction ?? 0;

              final opPanel = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OPERATIONAL', style: AppTextStyles.eyebrow),
                  const SizedBox(height: 12),
                  _buildKPIGrid([
                    KPICard(
                      title: 'Total Units in Stock',
                      value: '${_totalUnits(state)}',
                      icon: Icons.inventory_2,
                    ),
                    KPICard(
                      title: 'Items Below ROP',
                      value: '${state.lowStockItems}',
                      icon: Icons.warning_amber,
                      isAlert: state.lowStockItems > 0,
                      color: AppColors.warning,
                    ),
                    KPICard(
                      title: 'Open Recommendations',
                      value: '${state.openRecommendations}',
                      icon: Icons.assignment_late,
                      color: AppColors.primary,
                    ),
                    KPICard(
                      title: 'Forecast Accuracy',
                      value: state.forecastAccuracy > 0
                          ? '${(state.forecastAccuracy * 100).toStringAsFixed(1)}%'
                          : 'N/A',
                      icon: Icons.auto_graph,
                      color: AppColors.success,
                    ),
                  ]),
                ],
              );

              final mfgPanel = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MANUFACTURING', style: AppTextStyles.eyebrow),
                  const SizedBox(height: 12),
                  _buildKPIGrid([
                    KPICard(
                      title: 'Pending Material Orders',
                      value: '$pendingMaterialOrders',
                      icon: Icons.local_shipping,
                      isAlert: pendingMaterialOrders > 0,
                      color: AppColors.warning,
                    ),
                    KPICard(
                      title: 'Active Production Orders',
                      value: '$activeProductionOrders',
                      icon: Icons.precision_manufacturing,
                      color: AppColors.accent,
                    ),
                    KPICard(
                      title: 'Budget Remaining',
                      value:
                          'EGP ${(budgetRemaining - allocatedBudget).toStringAsFixed(0)}',
                      icon: Icons.account_balance,
                      isAlert: (budgetRemaining - allocatedBudget) < 0,
                      color: AppColors.success,
                    ),
                    KPICard(
                      title: 'Allocated to Production',
                      value: 'EGP ${allocatedBudget.toStringAsFixed(0)}',
                      icon: Icons.payments,
                      color: AppColors.primary,
                    ),
                  ]),
                ],
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: opPanel),
                    const SizedBox(width: 24),
                    Expanded(child: mfgPanel),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [opPanel, const SizedBox(height: 24), mfgPanel],
              );
            },
          ),

          const SizedBox(height: 24),

          // ── Charts Row ───────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 1000;
              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: isWide ? 3 : 0,
                    child: _buildCostBreakdownChart(
                        cogs, holdingCost, openOrderCost),
                  ),
                  SizedBox(width: isWide ? 24 : 0, height: isWide ? 0 : 24),
                  Expanded(
                    flex: isWide ? 2 : 0,
                    child: _buildCashFlowChart(cashFlow),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          // ── Demand vs Forecast ───────────────────────────────────────
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Demand vs Forecast (Last 6M)', style: AppTextStyles.h3),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 250,
                    child: _buildDemandForecastChart(state),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Top Expense Products Table ───────────────────────────────
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Top Expense Products', style: AppTextStyles.h3),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Product')),
                        DataColumn(label: Text('Monthly Forecast')),
                        DataColumn(label: Text('Unit Cost')),
                        DataColumn(label: Text('Monthly Spend')),
                        DataColumn(label: Text('% of Total')),
                      ],
                      rows: topProducts.take(10).map((p) {
                        final pct = totalSpend > 0
                            ? (p.monthlySpend / totalSpend * 100)
                            : 0.0;
                        return DataRow(cells: [
                          DataCell(Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(p.name,
                                  style: AppTextStyles.body
                                      .copyWith(fontWeight: FontWeight.w600)),
                              Text(p.sku, style: AppTextStyles.label),
                            ],
                          )),
                          DataCell(Text('${p.monthlyForecast}')),
                          DataCell(Text('EGP ${p.unitCost.toStringAsFixed(2)}')),
                          DataCell(Text(
                              'EGP ${p.monthlySpend.toStringAsFixed(0)}')),
                          DataCell(Text('${pct.toStringAsFixed(1)}%')),
                        ]);
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Supplier Cost Breakdown ──────────────────────────────────
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Supplier Cost Breakdown', style: AppTextStyles.h3),
                  const SizedBox(height: 16),
                  HorizontallyScrollableTable(
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Supplier')),
                        DataColumn(label: Text('# Products')),
                        DataColumn(label: Text('Avg Lead Time')),
                        DataColumn(label: Text('Monthly Spend')),
                      ],
                      rows: supplierCosts.map((s) {
                        return DataRow(cells: [
                          DataCell(Text(s.name,
                              style: AppTextStyles.body
                                  .copyWith(fontWeight: FontWeight.w600))),
                          DataCell(Text('${s.productCount}')),
                          DataCell(Text(
                              '${s.avgLeadTime.toStringAsFixed(0)} days')),
                          DataCell(Text(
                              'EGP ${s.totalMonthlySpend.toStringAsFixed(0)}')),
                        ]);
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-widgets ──────────────────────────────────────────────────────────

  /// Critical stock urgency banner with a per-product action table.
  /// Shown only when there is at least one product with current stock below
  /// its computed minimum (cycle + safety stock).
  Widget _buildCriticalStockSection(AppState state) {
    final critical = state.criticalStockProducts;
    if (critical.isEmpty) return const SizedBox.shrink();

    final mostUrgent = critical.first;
    final minDays = critical
        .map((r) => r.daysOfStockLeft.isFinite ? r.daysOfStockLeft : 9999.0)
        .reduce((a, b) => a < b ? a : b);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${critical.length} product${critical.length > 1 ? 's' : ''} '
                    'critically low — stockout in ~${minDays.toStringAsFixed(0)} day'
                    '${minDays.round() == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                        fontSize: 13),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.show_chart, size: 16),
                  label: const Text('Run Forecast Now →'),
                  onPressed: () => context
                      .go('/forecasts?productId=${mostUrgent.productId}'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          // Critical products table (top 5)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1.5),
                1: FlexColumnWidth(2.4),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1.1),
                4: FlexColumnWidth(1.1),
                5: FlexColumnWidth(1.4),
              },
              children: [
                TableRow(
                  children: ['SKU', 'Product', 'Current', 'Min', 'Days Left', '']
                      .map((h) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(h,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.error)),
                          ))
                      .toList(),
                ),
                ...critical.take(5).map((r) {
                  final days = r.daysOfStockLeft.isFinite
                      ? r.daysOfStockLeft
                      : 0.0;
                  return TableRow(
                    children: [
                      Text(r.sku,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textPrimary)),
                      Text(r.productName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textPrimary)),
                      Text('${r.currentStock}',
                          style: const TextStyle(fontSize: 12)),
                      Text('${r.minimumStock}',
                          style: const TextStyle(fontSize: 12)),
                      Text('${days.toStringAsFixed(0)} d',
                          style: TextStyle(
                              fontSize: 12,
                              color: days < 3
                                  ? AppColors.error
                                  : AppColors.warning,
                              fontWeight: FontWeight.w700)),
                      InkWell(
                        onTap: () => context
                            .go('/forecasts?productId=${r.productId}'),
                        child: const Text('Forecast →',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]
                        .map((w) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: w,
                            ))
                        .toList(),
                  );
                }),
              ],
            ),
          ),
          if (critical.length > 5)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '+ ${critical.length - 5} more — see Forecasts page',
                style: AppTextStyles.label
                    .copyWith(color: AppColors.error.withValues(alpha: 0.85)),
              ),
            ),
        ],
      ),
    );
  }

  /// Secondary lower-severity card surfacing pending replenishment
  /// recommendations (not a true stockout-risk alert).
  Widget _buildOpenRecsCard(AppState state) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningBg.withValues(alpha: 0.5),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_late_outlined,
              size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${state.openRecommendations} replenishment recommendation'
              '${state.openRecommendations > 1 ? 's' : ''} pending review',
              style: AppTextStyles.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => context.go('/replenishment'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.warning,
              textStyle:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Review →'),
          ),
        ],
      ),
    );
  }

  Widget _buildShopifyBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.store, color: AppColors.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Connect your Shopify store', style: AppTextStyles.h3),
                Text('Sync products and inventory in real-time.',
                    style: AppTextStyles.body),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => context.go('/integrations'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Connect Store'),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _showBanner = false),
          ),
        ],
      ),
    );
  }

  Widget _buildOnboardingChecklist(AppState state) {
    final steps = [
      _ChecklistStep(
        label: 'Connect Shopify or add products',
        route: '/integrations',
        isDone: state.products.isNotEmpty,
      ),
      _ChecklistStep(
        label: 'Add at least one supplier',
        route: '/suppliers',
        isDone: state.suppliers.isNotEmpty,
      ),
      _ChecklistStep(
        label: 'Add a warehouse',
        route: '/warehouses',
        isDone: state.warehouses.isNotEmpty,
      ),
      _ChecklistStep(
        label: 'Import demand data',
        route: '/demand-data',
        isDone: state.demandByProduct.isNotEmpty,
      ),
      _ChecklistStep(
        label: 'Run your first forecast',
        route: '/forecasts',
        isDone: state.currentForecast != null,
      ),
      _ChecklistStep(
        label: 'Configure EOQ & holding cost in Settings',
        route: '/settings',
        isDone: state.settings.orderingCost != 250.0 || state.settings.holdingRate != 0.20,
      ),
    ];
    final doneCount = steps.where((s) => s.isDone).length;
    final allDone = doneCount == steps.length;

    // Auto-hide if everything is done
    if (allDone) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.05),
            AppColors.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rocket_launch_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Get started — $doneCount of ${steps.length} complete',
                  style: AppTextStyles.h3.copyWith(color: AppColors.primary)),
              const Spacer(),
              // Progress bar
              SizedBox(
                width: 80,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: doneCount / steps.length,
                    minHeight: 6,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setState(() => _showChecklist = false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: steps
                .map((s) => _buildChecklistStep(context, s))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistStep(BuildContext context, _ChecklistStep step) {
    return InkWell(
      onTap: step.isDone ? null : () => context.go(step.route),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: step.isDone
              ? AppColors.success.withValues(alpha: 0.1)
              : Colors.white,
          border: Border.all(
            color: step.isDone
                ? AppColors.success.withValues(alpha: 0.4)
                : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              step.isDone
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 16,
              color: step.isDone
                  ? AppColors.success
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              step.label,
              style: AppTextStyles.bodySmall.copyWith(
                color: step.isDone
                    ? AppColors.success
                    : AppColors.textPrimary,
                decoration:
                    step.isDone ? TextDecoration.lineThrough : null,
                fontWeight: step.isDone ? FontWeight.normal : FontWeight.w500,
              ),
            ),
            if (!step.isDone) ...[
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_ios,
                  size: 10, color: AppColors.primary),
            ],
          ],
        ),
      ),
    );
  }

  // ── Hero card ────────────────────────────────────────────────────────────

  Widget _buildHeroCard(
      AppState state, double cogs, double holdingCost, double openOrderCost) {
    final accuracy = state.forecastAccuracy > 0
        ? '${(state.forecastAccuracy * 100).toStringAsFixed(1)}%'
        : '—';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      decoration: BoxDecoration(
        color: AppColors.sidebarBg,
        borderRadius: AppRadius.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'INVENTORY VALUE',
            style: AppTextStyles.eyebrow
                .copyWith(color: Colors.white.withValues(alpha: 0.45)),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'EGP ${state.totalStockValue.toStringAsFixed(0)}',
                style: AppTextStyles.display.copyWith(color: Colors.white),
              ),
              const SizedBox(width: 14),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${state.products.length} products · ${_totalUnits(state)} units',
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(
              color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 20),
          IntrinsicHeight(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _heroSubMetric('MONTHLY COGS',
                      'EGP ${cogs.toStringAsFixed(0)}'),
                  VerticalDivider(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 40),
                  _heroSubMetric('HOLDING COST',
                      'EGP ${holdingCost.toStringAsFixed(0)}'),
                  VerticalDivider(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 40),
                  _heroSubMetric(
                    'OPEN ORDERS',
                    'EGP ${openOrderCost.toStringAsFixed(0)}',
                    isAlert: openOrderCost > 0,
                  ),
                  VerticalDivider(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 40),
                  _heroSubMetric('FORECAST ACC.', accuracy),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroSubMetric(String label, String value,
      {bool isAlert = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.eyebrow
              .copyWith(color: Colors.white.withValues(alpha: 0.4)),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: AppTextStyles.mono.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: isAlert && value != 'EGP 0'
                ? AppColors.warning
                : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildKPIGrid(List<Widget> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w > 900 ? 4 : w > 500 ? 2 : 1;
        const spacing = 16.0;
        final cardW = (w - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map((c) => SizedBox(width: cardW, child: c))
              .toList(),
        );
      },
    );
  }

  Widget _buildCostBreakdownChart(
      double cogs, double holdingCost, double openOrderCost) {
    final total = cogs + holdingCost + openOrderCost;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monthly Cost Breakdown', style: AppTextStyles.h3),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: total == 0
                  ? const Center(child: Text('No cost data yet.'))
                  : PieChart(PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      sections: [
                        PieChartSectionData(
                          value: cogs,
                          title:
                              '${(cogs / total * 100).toStringAsFixed(0)}%',
                          color: AppColors.primary,
                          radius: 50,
                          titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                        PieChartSectionData(
                          value: holdingCost,
                          title:
                              '${(holdingCost / total * 100).toStringAsFixed(0)}%',
                          color: AppColors.warning,
                          radius: 50,
                          titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                        PieChartSectionData(
                          value: openOrderCost,
                          title:
                              '${(openOrderCost / total * 100).toStringAsFixed(0)}%',
                          color: AppColors.error,
                          radius: 50,
                          titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                      ],
                    )),
            ),
            const SizedBox(height: 12),
            _legendItem(AppColors.primary, 'COGS',
                'EGP ${cogs.toStringAsFixed(0)}'),
            _legendItem(AppColors.warning, 'Holding',
                'EGP ${holdingCost.toStringAsFixed(0)}'),
            _legendItem(AppColors.error, 'Open Orders',
                'EGP ${openOrderCost.toStringAsFixed(0)}'),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(width: 12, height: 12, color: color),
          const SizedBox(width: 8),
          Text(label, style: AppTextStyles.body),
          const Spacer(),
          Text(value,
              style:
                  AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildCashFlowChart(List<double> cashFlow) {
    final months = ['Month 1', 'Month 2', 'Month 3'];
    final maxY = cashFlow.isEmpty
        ? 100.0
        : cashFlow.reduce((a, b) => a > b ? a : b) * 1.2;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cash Flow Projection (3M)', style: AppTextStyles.h3),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= months.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(months[i],
                                style: AppTextStyles.label),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: cashFlow.asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value,
                          color: AppColors.accent,
                          width: 40,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Projected monthly inventory spend: EGP ${cashFlow.isNotEmpty ? cashFlow.first.toStringAsFixed(0) : 0}',
              style: AppTextStyles.label,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemandForecastChart(AppState state) {
    final forecast = state.currentForecast;
    if (forecast == null || forecast.periods.isEmpty) {
      final allDemand = state.demandByProduct.values.isNotEmpty
          ? state.demandByProduct.values.first
          : [];
      final spots = allDemand
          .asMap()
          .entries
          .take(6)
          .map((e) => FlSpot(e.key.toDouble(), e.value.quantity.toDouble()))
          .toList();

      return LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(
            rightTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: AppColors.border),
          ),
          lineBarsData: [
            if (spots.isNotEmpty)
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: AppColors.primary,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.primary.withValues(alpha: 0.1),
                ),
              ),
          ],
        ),
      );
    }

    final take = forecast.periods.length.clamp(0, 6);
    final actualSpots = forecast.actualDemand
        .take(take)
        .toList()
        .asMap()
        .entries
        .where((e) => e.value > 0)
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    final forecastSpots = forecast.forecast
        .take(take)
        .toList()
        .asMap()
        .entries
        .where((e) => e.value > 0)
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(
          rightTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: AppColors.border),
        ),
        lineBarsData: [
          if (actualSpots.isNotEmpty)
            LineChartBarData(
              spots: actualSpots,
              isCurved: true,
              color: AppColors.textSecondary,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primary.withValues(alpha: 0.05),
              ),
            ),
          if (forecastSpots.isNotEmpty)
            LineChartBarData(
              spots: forecastSpots,
              isCurved: true,
              color: AppColors.primary,
              barWidth: 3,
              dashArray: [5, 5],
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }
}

// ── Data classes ────────────────────────────────────────────────────────────

class _ProductSpend {
  final String name;
  final String sku;
  final int monthlyForecast;
  final double unitCost;
  final double monthlySpend;

  _ProductSpend({
    required this.name,
    required this.sku,
    required this.monthlyForecast,
    required this.unitCost,
    required this.monthlySpend,
  });
}

class _SupplierCost {
  final String name;
  final int productCount;
  final double avgLeadTime;
  final double totalMonthlySpend;

  _SupplierCost({
    required this.name,
    required this.productCount,
    required this.avgLeadTime,
    required this.totalMonthlySpend,
  });
}

class _ChecklistStep {
  final String label;
  final String route;
  final bool isDone;

  _ChecklistStep({
    required this.label,
    required this.route,
    required this.isDone,
  });
}
