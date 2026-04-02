import 'package:csv/csv.dart' show CsvEncoder;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/models/replenishment_recommendation.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/utils/download_helper.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class ReplenishmentScreen extends StatefulWidget {
  const ReplenishmentScreen({super.key});

  @override
  State<ReplenishmentScreen> createState() => _ReplenishmentScreenState();
}

class _ReplenishmentScreenState extends State<ReplenishmentScreen> {
  String _searchQuery = '';

  void _exportCsv(
    BuildContext context,
    List<ReplenishmentRecommendation> recs,
    Map<String, dynamic> productMap,
  ) {
    final rows = <List<dynamic>>[
      ['Product', 'SKU', 'Stock', 'Forecast', 'ROP', 'Suggested Qty', 'Status'],
      ...recs.map((r) => [
            r.productName,
            r.sku,
            r.currentStock,
            r.forecastNextPeriod,
            r.reorderPoint,
            r.suggestedOrderQty,
            r.status,
          ]),
    ];
    final csvString = const CsvEncoder().convert(rows);

    if (kIsWeb) {
      downloadCsvWeb(csvString, 'replenishment_export.csv');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV downloaded')),
      );
    } else {
      // Non-web fallback: show in a dialog
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('CSV Export'),
          content: SingleChildScrollView(child: SelectableText(csvString)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildApproveButton(BuildContext context, ReplenishmentRecommendation r) {
    final approved = context.watch<AppState>().approvedRecommendations;
    if (approved.contains(r.productId)) {
      return const Chip(
        label: Text('Approved', style: TextStyle(color: Colors.white, fontSize: 12)),
        backgroundColor: AppColors.success,
      );
    }
    return TextButton(
      onPressed: () async {
        await context.read<AppState>().approveRecommendation(r);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order for ${r.productName} approved!')),
          );
        }
      },
      child: const Text('Approve'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final productMap = {for (final p in state.products) p.id: p};

    final List<ReplenishmentRecommendation> recommendations = state
        .recommendations
        .where((r) {
          if (_searchQuery.isEmpty) return true;
          return r.productName.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              r.sku.toLowerCase().contains(_searchQuery.toLowerCase());
        })
        .toList();

    final totalSuggested = recommendations.fold<int>(
      0,
      (s, r) => s + r.suggestedOrderQty,
    );
    final needingAction = recommendations
        .where((r) => r.status == 'Critical' || r.status == 'Order Now')
        .length;
    final estimatedCost = recommendations.fold<double>(0, (sum, r) {
      final product = productMap[r.productId];
      return sum + r.estimatedCost(product?.unitCost ?? 0);
    });

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // KPIs
          Row(
            children: [
              Expanded(
                child: KPICard(
                  title: 'Total Units Suggested',
                  value: '$totalSuggested',
                  icon: Icons.shopping_bag,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Products Needing Action',
                  value: '$needingAction',
                  icon: Icons.warning_amber,
                  color: AppColors.warning,
                  isAlert: needingAction > 0,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Est. Order Cost',
                  value: '\$${estimatedCost.toStringAsFixed(0)}',
                  icon: Icons.attach_money,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Search by SKU or Name',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _searchQuery = ''),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => _exportCsv(context, recommendations, productMap),
                        icon: const Icon(Icons.download),
                        label: const Text('Export'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      if (needingAction > 0) ...[
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: () => context.go('/orders/create'),
                          icon: const Icon(Icons.shopping_cart),
                          label: const Text('Create Order'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  recommendations.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: AppColors.success,
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No replenishment needed — all stock levels are healthy.',
                                style: AppTextStyles.body.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : SizedBox(
                          width: double.infinity,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Product')),
                              DataColumn(label: Text('Stock')),
                              DataColumn(label: Text('Forecast (Next M)')),
                              DataColumn(label: Text('ROP')),
                              DataColumn(label: Text('Suggested Qty')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Action')),
                            ],
                            rows: recommendations.map((r) {
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Row(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: Colors.grey[200],
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.inventory,
                                            size: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              r.productName,
                                              style: AppTextStyles.body
                                                  .copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                            Text(
                                              r.sku,
                                              style: AppTextStyles.label,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(Text('${r.currentStock}')),
                                  DataCell(Text('${r.forecastNextPeriod}')),
                                  DataCell(Text('${r.reorderPoint}')),
                                  DataCell(
                                    Text(
                                      '${r.suggestedOrderQty}',
                                      style: AppTextStyles.body.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  DataCell(StatusChip(r.status)),
                                  DataCell(
                                    _buildApproveButton(context, r),
                                  ),
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
}
