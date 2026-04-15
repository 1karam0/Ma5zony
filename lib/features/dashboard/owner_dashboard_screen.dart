import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
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
    const annualHoldingRate = 0.20; // 20 % per year
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Shopify banner ───────────────────────────────────────────
          if (_showBanner && state.shopifyConnection?.isConnected != true)
            _buildShopifyBanner(),

          // ── Financial KPIs ───────────────────────────────────────────
          Text('Financial Overview', style: AppTextStyles.h2),
          const SizedBox(height: 16),
          _buildKPIGrid([
            KPICard(
              title: 'Total Inventory Value',
              value: '\$${state.totalStockValue.toStringAsFixed(0)}',
              icon: Icons.account_balance_wallet,
              color: AppColors.primary,
            ),
            KPICard(
              title: 'Monthly COGS',
              value: '\$${cogs.toStringAsFixed(0)}',
              icon: Icons.receipt_long,
              color: AppColors.accent,
            ),
            KPICard(
              title: 'Monthly Holding Cost',
              value: '\$${holdingCost.toStringAsFixed(0)}',
              icon: Icons.warehouse,
              color: AppColors.warning,
            ),
            KPICard(
              title: 'Open Order Cost',
              value: '\$${openOrderCost.toStringAsFixed(0)}',
              icon: Icons.shopping_cart_checkout,
              isAlert: openOrderCost > 0,
              color: AppColors.error,
            ),
          ]),

          const SizedBox(height: 24),

          // ── Operational KPIs ─────────────────────────────────────────
          Text('Operational Overview', style: AppTextStyles.h2),
          const SizedBox(height: 16),
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
                          DataCell(Text('\$${p.unitCost.toStringAsFixed(2)}')),
                          DataCell(Text(
                              '\$${p.monthlySpend.toStringAsFixed(0)}')),
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
                  SizedBox(
                    width: double.infinity,
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
                              '\$${s.totalMonthlySpend.toStringAsFixed(0)}')),
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

  Widget _buildKPIGrid(List<Widget> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int crossAxisCount =
            constraints.maxWidth > 1200 ? 4 : (constraints.maxWidth > 800 ? 2 : 1);
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.0,
          physics: const NeverScrollableScrollPhysics(),
          children: cards,
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
                '\$${cogs.toStringAsFixed(0)}'),
            _legendItem(AppColors.warning, 'Holding',
                '\$${holdingCost.toStringAsFixed(0)}'),
            _legendItem(AppColors.error, 'Open Orders',
                '\$${openOrderCost.toStringAsFixed(0)}'),
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
              'Projected monthly inventory spend: \$${cashFlow.isNotEmpty ? cashFlow.first.toStringAsFixed(0) : 0}',
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
