import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _showBanner = true;
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final products = state.products;
    final recommendations = state.recommendations;
    final warehouses = state.warehouses;

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shopify banner
          if (_showBanner && state.shopifyConnection?.isConnected != true)
            Container(
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
                        Text(
                          'Connect your Shopify store',
                          style: AppTextStyles.h3,
                        ),
                        Text(
                          'Sync products and inventory in real-time.',
                          style: AppTextStyles.body,
                        ),
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
            ),

          // KPI Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final double width = constraints.maxWidth;
              final int crossAxisCount = width > 1200
                  ? 4
                  : (width > 800 ? 2 : 1);

              return GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 2.0,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  KPICard(
                    title: 'Total Units in Stock',
                    value: '${products.fold<int>(0, (sum, p) => sum + p.currentStock)}',
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
                ],
              );
            },
          ),

          // ── Suggestion Action Buttons ──────────────────────────────
          if (state.lowStockItems > 0 || state.openRecommendations > 0)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Card(
                color: Colors.orange.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.orange.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          color: Colors.orange, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${state.lowStockItems} item(s) need attention',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrange,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Review replenishment or manufacturing suggestions to keep stock healthy.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => context.go('/replenishment'),
                        icon: const Icon(Icons.shopping_cart, size: 18),
                        label: const Text('Purchase Suggestions'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => context.go('/recommendations'),
                        icon: const Icon(Icons.precision_manufacturing,
                            size: 18),
                        label: const Text('Manufacturing Suggestions'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Shopify Sync Controls ─────────────────────────────────
          if (state.shopifyConnection?.isConnected == true)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.store,
                          color: AppColors.success, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Shopify Connected: ${state.shopifyConnection!.shopDomain}',
                              style: AppTextStyles.body
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              state.shopifyConnection!.lastSyncAt != null
                                  ? 'Last synced: ${_formatTimestamp(state.shopifyConnection!.lastSyncAt!)}'
                                  : 'Not synced yet',
                              style: AppTextStyles.label,
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _syncing
                            ? null
                            : () => _syncShopify(context, state),
                        icon: _syncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.sync, size: 18),
                        label: Text(_syncing ? 'Syncing...' : 'Sync Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Charts Section
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 1000;
              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Demand vs Forecast chart (uses currentForecast if available)
                  Expanded(
                    flex: isWide ? 3 : 0,
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Demand vs Forecast (Last 6M)',
                              style: AppTextStyles.h3,
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 250,
                              child: _buildDemandForecastChart(state),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isWide ? 24 : 0, height: isWide ? 0 : 24),
                  // Stock by warehouse bar chart
                  Expanded(
                    flex: isWide ? 2 : 0,
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Stock by Warehouse', style: AppTextStyles.h3),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 250,
                              child: BarChart(
                                BarChartData(
                                  gridData: const FlGridData(show: false),
                                  titlesData: FlTitlesData(
                                    rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    leftTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: false,
                                        getTitlesWidget: (v, _) =>
                                            const SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  barGroups: warehouses
                                      .asMap()
                                      .entries
                                      .map(
                                        (e) => BarChartGroupData(
                                          x: e.key,
                                          barRods: [
                                            BarChartRodData(
                                              toY: e.value.totalStock
                                                  .toDouble(),
                                              color: e.key == 0
                                                  ? AppColors.primary
                                                  : AppColors.accent,
                                              width: 30,
                                            ),
                                          ],
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...warehouses.asMap().entries.map(
                              (e) => Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    color: e.key == 0
                                        ? AppColors.primary
                                        : AppColors.accent,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${e.value.name}: ${e.value.totalStock} units',
                                    style: AppTextStyles.label,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          // Quick Inventory Overview with replenishment data
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quick Inventory Overview', style: AppTextStyles.h3),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Product')),
                        DataColumn(
                          label: Text(
                            'Current Stock',
                            textAlign: TextAlign.right,
                          ),
                        ),
                        DataColumn(
                          label: Text('ROP', textAlign: TextAlign.right),
                        ),
                        DataColumn(
                          label: Text('Suggested', textAlign: TextAlign.right),
                        ),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: products.take(5).map((p) {
                        final rec = recommendations
                            .where((r) => r.productId == p.id)
                            .firstOrNull;
                        final rop = rec?.reorderPoint ?? 0;
                        final suggested = rec?.suggestedOrderQty ?? 0;
                        final status = p.currentStock == 0
                            ? 'Critical'
                            : (p.currentStock <= rop && rop > 0 ? 'Low' : 'OK');

                        return DataRow(
                          cells: [
                            DataCell(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    p.name,
                                    style: AppTextStyles.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(p.sku, style: AppTextStyles.label),
                                ],
                              ),
                            ),
                            DataCell(Text('${p.currentStock}')),
                            DataCell(Text('$rop')),
                            DataCell(Text(rec != null ? '$suggested' : '-')),
                            DataCell(StatusChip(status)),
                          ],
                        );
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

  Future<void> _syncShopify(BuildContext context, AppState state) async {
    setState(() => _syncing = true);
    try {
      await state.syncShopifyInventory();
      final orderResult = await state.importShopifyOrders();
      if (context.mounted) {
        final imported = orderResult?['newRecordsImported'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Shopify synced! Inventory updated, $imported new demand records imported.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Widget _buildDemandForecastChart(AppState state) {
    final forecast = state.currentForecast;
    if (forecast == null || forecast.periods.isEmpty) {
      // Show a simple placeholder line chart using first product demand
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
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
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

    // Use computed ForecastResult
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
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
