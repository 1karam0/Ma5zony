import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

/// Deep-dive financial analytics screen (Owner-only).
///
/// Provides ABC analysis, inventory turnover, days of supply,
/// cost-by-category breakdown, dead-stock identification, and more.
class FinancialAnalyticsScreen extends StatefulWidget {
  const FinancialAnalyticsScreen({super.key});

  @override
  State<FinancialAnalyticsScreen> createState() =>
      _FinancialAnalyticsScreenState();
}

class _FinancialAnalyticsScreenState extends State<FinancialAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Header ──────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Financial Analytics', style: AppTextStyles.h1),
              const SizedBox(height: 4),
              Text(
                'In-depth cost analysis, inventory valuation, and efficiency metrics.',
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ── Tabs ────────────────────────────────────────────────
        TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Cost Analysis'),
            Tab(text: 'Inventory Valuation'),
            Tab(text: 'Efficiency Metrics'),
          ],
        ),
        // ── Tab Content ────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _CostAnalysisTab(),
              _InventoryValuationTab(),
              _EfficiencyMetricsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab 1 — Cost Analysis
// ═══════════════════════════════════════════════════════════════════════════

class _CostAnalysisTab extends StatelessWidget {
  const _CostAnalysisTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final categoryData = _costByCategory(state);
    final supplierData = _costBySupplier(state);
    final monthlyTrend = _monthlySpendTrend(state);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Summary KPIs ─────────────────────────────────────────
          _buildSummaryRow(state),
          const SizedBox(height: 24),

          // ── Charts Row ───────────────────────────────────────────
          LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth > 1000;
            return Flex(
              direction: isWide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: isWide ? 1 : 0,
                  child: _buildCategoryPieChart(categoryData),
                ),
                SizedBox(width: isWide ? 24 : 0, height: isWide ? 0 : 24),
                Expanded(
                  flex: isWide ? 1 : 0,
                  child: _buildSupplierBarChart(supplierData),
                ),
              ],
            );
          }),
          const SizedBox(height: 24),

          // ── Monthly Spend Trend ──────────────────────────────────
          _buildMonthlyTrendChart(monthlyTrend),
          const SizedBox(height: 24),

          // ── Category Detail Table ────────────────────────────────
          _buildCategoryTable(categoryData),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(AppState state) {
    final totalInventoryValue = state.totalStockValue;
    final monthlyCogs = _calcMonthlyCOGS(state);
    final annualHolding = totalInventoryValue * 0.20;
    final avgUnitCost = state.products.isEmpty
        ? 0.0
        : state.products.fold<double>(0, (s, p) => s + p.unitCost) /
            state.products.length;

    return LayoutBuilder(builder: (context, constraints) {
      final crossAxisCount =
          constraints.maxWidth > 1200 ? 4 : (constraints.maxWidth > 600 ? 2 : 1);
      return GridView.count(
        crossAxisCount: crossAxisCount,
        shrinkWrap: true,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 2.2,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          KPICard(
            title: 'Total Inventory Value',
            value: '\$${totalInventoryValue.toStringAsFixed(0)}',
            icon: Icons.account_balance_wallet,
            color: AppColors.primary,
          ),
          KPICard(
            title: 'Monthly COGS',
            value: '\$${monthlyCogs.toStringAsFixed(0)}',
            icon: Icons.receipt_long,
            color: AppColors.accent,
          ),
          KPICard(
            title: 'Annual Holding Cost',
            value: '\$${annualHolding.toStringAsFixed(0)}',
            icon: Icons.warehouse,
            color: AppColors.warning,
          ),
          KPICard(
            title: 'Avg Unit Cost',
            value: '\$${avgUnitCost.toStringAsFixed(2)}',
            icon: Icons.calculate,
            color: AppColors.textSecondary,
          ),
        ],
      );
    });
  }

  // ── Category Pie Chart ───────────────────────────────────────────────

  Widget _buildCategoryPieChart(List<_CategoryCost> data) {
    final total = data.fold<double>(0, (s, c) => s + c.value);
    final colors = [
      AppColors.primary,
      AppColors.accent,
      AppColors.warning,
      AppColors.error,
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFF6366F1),
      const Color(0xFF14B8A6),
    ];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cost by Category', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: total == 0
                  ? const Center(child: Text('No data'))
                  : PieChart(PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      sections: data.asMap().entries.map((e) {
                        final color = colors[e.key % colors.length];
                        final pct = e.value.value / total * 100;
                        return PieChartSectionData(
                          value: e.value.value,
                          title: pct >= 5
                              ? '${pct.toStringAsFixed(0)}%'
                              : '',
                          color: color,
                          radius: 50,
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        );
                      }).toList(),
                    )),
            ),
            const SizedBox(height: 12),
            ...data.asMap().entries.map((e) {
              final color = colors[e.key % colors.length];
              return _legendItem(
                color,
                e.value.category,
                '\$${e.value.value.toStringAsFixed(0)}',
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Supplier Bar Chart ───────────────────────────────────────────────

  Widget _buildSupplierBarChart(List<_SupplierSpend> data) {
    if (data.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: Text('No supplier data')),
        ),
      );
    }
    final maxY =
        data.map((s) => s.spend).reduce(max) * 1.2;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spend by Supplier', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(BarChartData(
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
                      reservedSize: 40,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= data.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            data[i].name.length > 8
                                ? '${data[i].name.substring(0, 8)}…'
                                : data[i].name,
                            style: AppTextStyles.label,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: data.asMap().entries.map((e) {
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.spend,
                        color: AppColors.primary,
                        width: 30,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              )),
            ),
          ],
        ),
      ),
    );
  }

  // ── Monthly Spend Trend (last 6 months) ──────────────────────────────

  Widget _buildMonthlyTrendChart(List<_MonthlySpend> data) {
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxY = data.map((m) => m.spend).reduce(max) * 1.2;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monthly Spend Trend', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: LineChart(LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: AppColors.border),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= data.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(data[i].label, style: AppTextStyles.label),
                        );
                      },
                    ),
                  ),
                ),
                maxY: maxY,
                minY: 0,
                lineBarsData: [
                  LineChartBarData(
                    spots: data
                        .asMap()
                        .entries
                        .map((e) =>
                            FlSpot(e.key.toDouble(), e.value.spend))
                        .toList(),
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              )),
            ),
          ],
        ),
      ),
    );
  }

  // ── Category Detail Table ────────────────────────────────────────────

  Widget _buildCategoryTable(List<_CategoryCost> data) {
    final total = data.fold<double>(0, (s, c) => s + c.value);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Category Cost Detail', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Category')),
                  DataColumn(label: Text('# Products')),
                  DataColumn(label: Text('Inventory Value')),
                  DataColumn(label: Text('% of Total')),
                ],
                rows: data.map((c) {
                  final pct =
                      total > 0 ? (c.value / total * 100) : 0.0;
                  return DataRow(cells: [
                    DataCell(Text(c.category,
                        style: AppTextStyles.body
                            .copyWith(fontWeight: FontWeight.w600))),
                    DataCell(Text('${c.productCount}')),
                    DataCell(
                        Text('\$${c.value.toStringAsFixed(0)}')),
                    DataCell(Text('${pct.toStringAsFixed(1)}%')),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers  ─────────────────────────────────────────────────────────

  static double _calcMonthlyCOGS(AppState state) {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    double cogs = 0;
    for (final entry in state.demandByProduct.entries) {
      final product =
          state.products.where((p) => p.id == entry.key).firstOrNull;
      if (product == null) continue;
      for (final d in entry.value) {
        if (d.periodStart.isAfter(thirtyDaysAgo)) {
          cogs += d.quantity * product.unitCost;
        }
      }
    }
    return cogs;
  }

  static List<_CategoryCost> _costByCategory(AppState state) {
    final map = <String, _CategoryCost>{};
    for (final p in state.products) {
      final value = p.currentStock * p.unitCost;
      final cat = p.category.isEmpty ? 'Uncategorized' : p.category;
      if (map.containsKey(cat)) {
        map[cat] = _CategoryCost(
          category: cat,
          value: map[cat]!.value + value,
          productCount: map[cat]!.productCount + 1,
        );
      } else {
        map[cat] = _CategoryCost(
          category: cat,
          value: value,
          productCount: 1,
        );
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  static List<_SupplierSpend> _costBySupplier(AppState state) {
    final map = <String, double>{};
    final names = <String, String>{};
    for (final p in state.products) {
      final sid = p.supplierId;
      if (sid == null) continue;
      final supplier =
          state.suppliers.where((s) => s.id == sid).firstOrNull;
      names[sid] = supplier?.name ?? 'Unknown';
      map[sid] = (map[sid] ?? 0) + (p.currentStock * p.unitCost);
    }
    final list = map.entries
        .map((e) => _SupplierSpend(name: names[e.key]!, spend: e.value))
        .toList()
      ..sort((a, b) => b.spend.compareTo(a.spend));
    return list.take(8).toList();
  }

  static List<_MonthlySpend> _monthlySpendTrend(AppState state) {
    final now = DateTime.now();
    final months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final result = <_MonthlySpend>[];

    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final nextMonth = DateTime(month.year, month.month + 1, 1);
      double spend = 0;
      for (final entry in state.demandByProduct.entries) {
        final product =
            state.products.where((p) => p.id == entry.key).firstOrNull;
        if (product == null) continue;
        for (final d in entry.value) {
          if (!d.periodStart.isBefore(month) &&
              d.periodStart.isBefore(nextMonth)) {
            spend += d.quantity * product.unitCost;
          }
        }
      }
      result.add(_MonthlySpend(
        label: months[month.month - 1],
        spend: spend,
      ));
    }
    return result;
  }

  static Widget _legendItem(Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(width: 12, height: 12, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: AppTextStyles.body)),
          Text(value,
              style:
                  AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab 2 — Inventory Valuation (ABC Analysis + Dead Stock)
// ═══════════════════════════════════════════════════════════════════════════

class _InventoryValuationTab extends StatelessWidget {
  const _InventoryValuationTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final abcData = _abcAnalysis(state);
    final deadStock = _deadStockProducts(state);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── ABC Summary Cards ─────────────────────────────────────
          _buildABCSummary(abcData),
          const SizedBox(height: 24),

          // ── ABC Chart ─────────────────────────────────────────────
          _buildABCChart(abcData),
          const SizedBox(height: 24),

          // ── ABC Detail Table ──────────────────────────────────────
          _buildABCTable(abcData),
          const SizedBox(height: 24),

          // ── Dead / Slow-Moving Stock ────────────────────────────────
          _buildDeadStockSection(deadStock),
        ],
      ),
    );
  }

  Widget _buildABCSummary(List<_ABCProduct> data) {
    final aCount = data.where((p) => p.grade == 'A').length;
    final bCount = data.where((p) => p.grade == 'B').length;
    final cCount = data.where((p) => p.grade == 'C').length;

    return LayoutBuilder(builder: (context, constraints) {
      final crossAxisCount =
          constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 500 ? 2 : 1);
      return GridView.count(
        crossAxisCount: crossAxisCount,
        shrinkWrap: true,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 2.4,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          KPICard(
            title: 'A Items (Top 80%)',
            value: '$aCount products',
            icon: Icons.star,
            color: AppColors.error,
          ),
          KPICard(
            title: 'B Items (Next 15%)',
            value: '$bCount products',
            icon: Icons.star_half,
            color: AppColors.warning,
          ),
          KPICard(
            title: 'C Items (Bottom 5%)',
            value: '$cCount products',
            icon: Icons.star_border,
            color: AppColors.success,
          ),
        ],
      );
    });
  }

  Widget _buildABCChart(List<_ABCProduct> data) {
    final aValue =
        data.where((p) => p.grade == 'A').fold<double>(0, (s, p) => s + p.value);
    final bValue =
        data.where((p) => p.grade == 'B').fold<double>(0, (s, p) => s + p.value);
    final cValue =
        data.where((p) => p.grade == 'C').fold<double>(0, (s, p) => s + p.value);
    final total = aValue + bValue + cValue;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ABC Value Distribution', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: total == 0
                  ? const Center(child: Text('No products'))
                  : PieChart(PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      sections: [
                        if (aValue > 0)
                          PieChartSectionData(
                            value: aValue,
                            title:
                                'A\n${(aValue / total * 100).toStringAsFixed(0)}%',
                            color: AppColors.error,
                            radius: 55,
                            titleStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                        if (bValue > 0)
                          PieChartSectionData(
                            value: bValue,
                            title:
                                'B\n${(bValue / total * 100).toStringAsFixed(0)}%',
                            color: AppColors.warning,
                            radius: 50,
                            titleStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                        if (cValue > 0)
                          PieChartSectionData(
                            value: cValue,
                            title:
                                'C\n${(cValue / total * 100).toStringAsFixed(0)}%',
                            color: AppColors.success,
                            radius: 45,
                            titleStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                      ],
                    )),
            ),
            const SizedBox(height: 12),
            _legendItem(AppColors.error, 'A — High Value',
                '\$${aValue.toStringAsFixed(0)}'),
            _legendItem(AppColors.warning, 'B — Medium Value',
                '\$${bValue.toStringAsFixed(0)}'),
            _legendItem(AppColors.success, 'C — Low Value',
                '\$${cValue.toStringAsFixed(0)}'),
          ],
        ),
      ),
    );
  }

  Widget _buildABCTable(List<_ABCProduct> data) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Product ABC Classification', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Grade')),
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('Unit Cost')),
                  DataColumn(label: Text('Stock')),
                  DataColumn(label: Text('Value')),
                  DataColumn(label: Text('Cumulative %')),
                ],
                rows: data.take(20).map((p) {
                  return DataRow(cells: [
                    DataCell(StatusChip(p.grade)),
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
                    DataCell(
                        Text('\$${p.unitCost.toStringAsFixed(2)}')),
                    DataCell(Text('${p.stock}')),
                    DataCell(
                        Text('\$${p.value.toStringAsFixed(0)}')),
                    DataCell(
                        Text('${p.cumulativePercent.toStringAsFixed(1)}%')),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeadStockSection(List<_DeadStockProduct> data) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber, color: AppColors.warning),
                const SizedBox(width: 8),
                Text('Dead / Slow-Moving Stock', style: AppTextStyles.h3),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Products with zero or very low demand in the last 30 days.',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 16),
            if (data.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No dead stock detected — all products have recent demand.'),
              )
            else
              SizedBox(
                width: double.infinity,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Product')),
                    DataColumn(label: Text('Stock')),
                    DataColumn(label: Text('Value Tied Up')),
                    DataColumn(label: Text('Last 30d Demand')),
                    DataColumn(label: Text('Status')),
                  ],
                  rows: data.map((p) {
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
                      DataCell(Text('${p.stock}')),
                      DataCell(Text(
                          '\$${p.valueTiedUp.toStringAsFixed(0)}')),
                      DataCell(Text('${p.recentDemand}')),
                      DataCell(StatusChip(
                          p.recentDemand == 0 ? 'Critical' : 'Low')),
                    ]);
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  /// ABC analysis: sort products by inventory value desc, assign A/B/C.
  static List<_ABCProduct> _abcAnalysis(AppState state) {
    if (state.products.isEmpty) return [];

    final sorted = List<Product>.from(state.products)
      ..sort((a, b) =>
          (b.currentStock * b.unitCost).compareTo(a.currentStock * a.unitCost));

    final totalValue =
        sorted.fold<double>(0, (s, p) => s + p.currentStock * p.unitCost);
    if (totalValue == 0) return [];

    double cumulative = 0;
    return sorted.map((p) {
      final value = p.currentStock * p.unitCost;
      cumulative += value;
      final cumulativePct = cumulative / totalValue * 100;
      String grade;
      if (cumulativePct <= 80) {
        grade = 'A';
      } else if (cumulativePct <= 95) {
        grade = 'B';
      } else {
        grade = 'C';
      }
      return _ABCProduct(
        name: p.name,
        sku: p.sku,
        unitCost: p.unitCost,
        stock: p.currentStock,
        value: value,
        cumulativePercent: cumulativePct,
        grade: grade,
      );
    }).toList();
  }

  /// Products with stock > 0 but zero or very low demand in last 30 days.
  static List<_DeadStockProduct> _deadStockProducts(AppState state) {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final result = <_DeadStockProduct>[];

    for (final p in state.products) {
      if (p.currentStock == 0) continue;
      final records = state.demandByProduct[p.id] ?? [];
      int recentDemand = 0;
      for (final d in records) {
        if (d.periodStart.isAfter(thirtyDaysAgo)) {
          recentDemand += d.quantity;
        }
      }
      // Consider "dead" if demand < 5% of current stock
      if (recentDemand <= (p.currentStock * 0.05).ceil()) {
        result.add(_DeadStockProduct(
          name: p.name,
          sku: p.sku,
          stock: p.currentStock,
          valueTiedUp: p.currentStock * p.unitCost,
          recentDemand: recentDemand,
        ));
      }
    }
    result.sort((a, b) => b.valueTiedUp.compareTo(a.valueTiedUp));
    return result;
  }

  static Widget _legendItem(Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(width: 12, height: 12, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: AppTextStyles.body)),
          Text(value,
              style:
                  AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab 3 — Efficiency Metrics
// ═══════════════════════════════════════════════════════════════════════════

class _EfficiencyMetricsTab extends StatelessWidget {
  const _EfficiencyMetricsTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final metrics = _computeMetrics(state);
    final productMetrics = _productEfficiency(state);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Global Metrics KPIs ─────────────────────────────────────
          _buildMetricsKPIs(metrics),
          const SizedBox(height: 24),

          // ── Days-of-Supply Chart ────────────────────────────────────
          _buildDaysOfSupplyChart(productMetrics),
          const SizedBox(height: 24),

          // ── Product Efficiency Table ────────────────────────────────
          _buildProductTable(productMetrics),
        ],
      ),
    );
  }

  Widget _buildMetricsKPIs(_GlobalMetrics metrics) {
    return LayoutBuilder(builder: (context, constraints) {
      final crossAxisCount =
          constraints.maxWidth > 1200 ? 4 : (constraints.maxWidth > 600 ? 2 : 1);
      return GridView.count(
        crossAxisCount: crossAxisCount,
        shrinkWrap: true,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 2.2,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          KPICard(
            title: 'Inventory Turnover',
            value: metrics.turnover > 0
                ? '${metrics.turnover.toStringAsFixed(1)}x'
                : 'N/A',
            icon: Icons.autorenew,
            color: AppColors.primary,
          ),
          KPICard(
            title: 'Avg Days of Supply',
            value: metrics.avgDaysOfSupply > 0
                ? '${metrics.avgDaysOfSupply.toStringAsFixed(0)} days'
                : 'N/A',
            icon: Icons.calendar_today,
            color: AppColors.accent,
          ),
          KPICard(
            title: 'Stockout Risk',
            value: '${metrics.stockoutRiskCount} items',
            icon: Icons.error_outline,
            isAlert: metrics.stockoutRiskCount > 0,
            color: AppColors.error,
          ),
          KPICard(
            title: 'Overstock Items',
            value: '${metrics.overstockCount} items',
            icon: Icons.inventory,
            isAlert: metrics.overstockCount > 0,
            color: AppColors.warning,
          ),
        ],
      );
    });
  }

  Widget _buildDaysOfSupplyChart(List<_ProductEfficiency> data) {
    final topProducts = data.take(10).toList();
    if (topProducts.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxY = topProducts
            .map((p) => p.daysOfSupply.clamp(0, 365).toDouble())
            .reduce(max) *
        1.2;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Days of Supply (Top 10 Products)', style: AppTextStyles.h3),
            const SizedBox(height: 4),
            Text(
              'How many days current stock will last at current demand rate.',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: BarChart(BarChartData(
                maxY: maxY == 0 ? 100 : maxY,
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
                      reservedSize: 50,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= topProducts.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: RotatedBox(
                            quarterTurns: 1,
                            child: Text(
                              topProducts[i].name.length > 10
                                  ? '${topProducts[i].name.substring(0, 10)}…'
                                  : topProducts[i].name,
                              style: AppTextStyles.label,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: topProducts.asMap().entries.map((e) {
                  final days = e.value.daysOfSupply.clamp(0, 365).toDouble();
                  Color color;
                  if (days < 7) {
                    color = AppColors.error;
                  } else if (days < 30) {
                    color = AppColors.warning;
                  } else {
                    color = AppColors.success;
                  }
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: days,
                        color: color,
                        width: 24,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              )),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _colorDot(AppColors.error),
                const SizedBox(width: 4),
                Text('< 7 days', style: AppTextStyles.label),
                const SizedBox(width: 16),
                _colorDot(AppColors.warning),
                const SizedBox(width: 4),
                Text('7–30 days', style: AppTextStyles.label),
                const SizedBox(width: 16),
                _colorDot(AppColors.success),
                const SizedBox(width: 4),
                Text('> 30 days', style: AppTextStyles.label),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductTable(List<_ProductEfficiency> data) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Product Efficiency Details', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('Stock')),
                  DataColumn(label: Text('Daily Demand')),
                  DataColumn(label: Text('Days of Supply')),
                  DataColumn(label: Text('Turnover')),
                  DataColumn(label: Text('Status')),
                ],
                rows: data.take(15).map((p) {
                  String status;
                  if (p.daysOfSupply < 7) {
                    status = 'Critical';
                  } else if (p.daysOfSupply < 30) {
                    status = 'Low';
                  } else if (p.daysOfSupply > 180) {
                    status = 'Overstock';
                  } else {
                    status = 'OK';
                  }
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
                    DataCell(Text('${p.stock}')),
                    DataCell(Text(p.dailyDemand.toStringAsFixed(1))),
                    DataCell(Text('${p.daysOfSupply}')),
                    DataCell(Text(p.turnover > 0
                        ? '${p.turnover.toStringAsFixed(1)}x'
                        : 'N/A')),
                    DataCell(StatusChip(status)),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  static _GlobalMetrics _computeMetrics(AppState state) {
    final products = state.products;
    if (products.isEmpty) {
      return _GlobalMetrics(
          turnover: 0,
          avgDaysOfSupply: 0,
          stockoutRiskCount: 0,
          overstockCount: 0);
    }

    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    double totalCOGS = 0;
    double totalDaysOfSupply = 0;
    int productCount = 0;
    int stockoutRisk = 0;
    int overstock = 0;

    for (final p in products) {
      final records = state.demandByProduct[p.id] ?? [];
      int recentDemand = 0;
      for (final d in records) {
        if (d.periodStart.isAfter(thirtyDaysAgo)) {
          recentDemand += d.quantity;
        }
      }
      totalCOGS += recentDemand * p.unitCost;
      final dailyDemand = recentDemand / 30.0;
      final daysOfSupply =
          dailyDemand > 0 ? (p.currentStock / dailyDemand).round() : 999;

      if (daysOfSupply < 7 && p.currentStock > 0) stockoutRisk++;
      if (daysOfSupply > 180) overstock++;

      totalDaysOfSupply += daysOfSupply.clamp(0, 365);
      productCount++;
    }

    final avgInventory = state.totalStockValue;
    final annualizedCOGS = totalCOGS * 12;
    final turnover =
        avgInventory > 0 ? annualizedCOGS / avgInventory : 0.0;

    return _GlobalMetrics(
      turnover: turnover,
      avgDaysOfSupply: productCount > 0
          ? totalDaysOfSupply / productCount
          : 0,
      stockoutRiskCount: stockoutRisk,
      overstockCount: overstock,
    );
  }

  static List<_ProductEfficiency> _productEfficiency(AppState state) {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final result = <_ProductEfficiency>[];

    for (final p in state.products) {
      final records = state.demandByProduct[p.id] ?? [];
      int recentDemand = 0;
      for (final d in records) {
        if (d.periodStart.isAfter(thirtyDaysAgo)) {
          recentDemand += d.quantity;
        }
      }
      final dailyDemand = recentDemand / 30.0;
      final daysOfSupply =
          dailyDemand > 0 ? (p.currentStock / dailyDemand).round() : 999;
      final annualCOGS = recentDemand * p.unitCost * 12;
      final inventoryValue = p.currentStock * p.unitCost;
      final turnover =
          inventoryValue > 0 ? annualCOGS / inventoryValue : 0.0;

      result.add(_ProductEfficiency(
        name: p.name,
        sku: p.sku,
        stock: p.currentStock,
        dailyDemand: dailyDemand,
        daysOfSupply: daysOfSupply,
        turnover: turnover,
      ));
    }
    // Sort by days of supply ascending (most urgent first)
    result.sort((a, b) => a.daysOfSupply.compareTo(b.daysOfSupply));
    return result;
  }

  static Widget _colorDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Data classes
// ═══════════════════════════════════════════════════════════════════════════

class _CategoryCost {
  final String category;
  final double value;
  final int productCount;
  _CategoryCost(
      {required this.category, required this.value, required this.productCount});
}

class _SupplierSpend {
  final String name;
  final double spend;
  _SupplierSpend({required this.name, required this.spend});
}

class _MonthlySpend {
  final String label;
  final double spend;
  _MonthlySpend({required this.label, required this.spend});
}

class _ABCProduct {
  final String name;
  final String sku;
  final double unitCost;
  final int stock;
  final double value;
  final double cumulativePercent;
  final String grade;
  _ABCProduct({
    required this.name,
    required this.sku,
    required this.unitCost,
    required this.stock,
    required this.value,
    required this.cumulativePercent,
    required this.grade,
  });
}

class _DeadStockProduct {
  final String name;
  final String sku;
  final int stock;
  final double valueTiedUp;
  final int recentDemand;
  _DeadStockProduct({
    required this.name,
    required this.sku,
    required this.stock,
    required this.valueTiedUp,
    required this.recentDemand,
  });
}

class _GlobalMetrics {
  final double turnover;
  final double avgDaysOfSupply;
  final int stockoutRiskCount;
  final int overstockCount;
  _GlobalMetrics({
    required this.turnover,
    required this.avgDaysOfSupply,
    required this.stockoutRiskCount,
    required this.overstockCount,
  });
}

class _ProductEfficiency {
  final String name;
  final String sku;
  final int stock;
  final double dailyDemand;
  final int daysOfSupply;
  final double turnover;
  _ProductEfficiency({
    required this.name,
    required this.sku,
    required this.stock,
    required this.dailyDemand,
    required this.daysOfSupply,
    required this.turnover,
  });
}
