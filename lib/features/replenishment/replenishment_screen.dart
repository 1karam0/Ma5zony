import 'package:csv/csv.dart' show CsvEncoder;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/supplier.dart';
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
  final Map<String, int> _adjustedQty = {};
  final Set<String> _selectedIds = {};
  bool _selectAll = false;
  bool _sortByPriority = true;
  final Map<String, bool> _approving = {};
  bool _bulkApproving = false;

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

  Widget _buildArrivalDate(
    ReplenishmentRecommendation r,
    Product? product,
    Map<String, Supplier> supplierMap,
  ) {
    if (product?.supplierId == null) {
      return const Text('—', style: TextStyle(color: Colors.grey));
    }
    final supplier = supplierMap[product!.supplierId!];
    if (supplier == null) {
      return const Text('—', style: TextStyle(color: Colors.grey));
    }
    final leadDays = supplier.typicalLeadTimeDays;
    final arrival = r.recommendedOrderDate.add(Duration(days: leadDays));
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(DateFormat('d MMM').format(arrival),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('+${leadDays}d', style: AppTextStyles.label),
      ],
    );
  }

  Widget _buildApproveButton(BuildContext context, ReplenishmentRecommendation r, Product? product) {
    final approved = context.watch<AppState>().approvedRecommendations;
    if (approved.contains(r.productId)) {
      return const Chip(
        label: Text('Approved', style: TextStyle(color: Colors.white, fontSize: 12)),
        backgroundColor: AppColors.success,
      );
    }
    final isManufacture = product?.manufacturerId != null && product!.manufacturerId!.isNotEmpty;
    final isApproving = _approving[r.productId] == true;
    return TextButton(
      onPressed: isApproving
          ? null
          : () => _approveSingle(context, r, isManufacture),
      child: isApproving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(isManufacture ? 'Manufacture' : 'Approve'),
    );
  }

  Future<void> _approveSingle(
    BuildContext context,
    ReplenishmentRecommendation r,
    bool isManufacture,
  ) async {
    setState(() => _approving[r.productId] = true);
    // Capture before any await.
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = GoRouter.of(context);
    try {
      final adjustedRec = _adjustedQty.containsKey(r.productId)
          ? r.copyWith(suggestedOrderQty: _adjustedQty[r.productId])
          : r;
      if (isManufacture) {
        await state.approveReplenishmentManufacture(adjustedRec);
      } else {
        await state.approveRecommendation(adjustedRec);
      }
      final count = state.lastApprovalEmailsSent;
      final emailNote = count > 0
          ? ' — $count email${count == 1 ? '' : 's'} sent'
          : isManufacture
              ? ' (no factory email on file)'
              : ' (no supplier email on file)';
      messenger.showSnackBar(SnackBar(
        content: Text('${r.productName} approved$emailNote'),
        backgroundColor: AppColors.success,
      ));
      if (isManufacture) {
        navigator.go('/recommendations');
      } else {
        navigator.go('/orders');
      }
    } on CloudFunctionException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Order created but email delivery failed: ${e.message}'),
        backgroundColor: AppColors.warning,
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _approving.remove(r.productId));
    }
  }

  Future<void> _approveSelected(BuildContext context, List<ReplenishmentRecommendation> recs, Map<String, Product> productMap) async {
    setState(() => _bulkApproving = true);
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = GoRouter.of(context);
    int purchaseCount = 0;
    int mfgCount = 0;
    int emailsFailed = 0;
    try {
      for (final r in recs) {
        if (!_selectedIds.contains(r.productId)) continue;
        if (state.approvedRecommendations.contains(r.productId)) continue;
        final adjustedRec = _adjustedQty.containsKey(r.productId)
            ? r.copyWith(suggestedOrderQty: _adjustedQty[r.productId])
            : r;
        final product = productMap[r.productId];
        final isManufacture = product?.manufacturerId != null &&
            product!.manufacturerId!.isNotEmpty;
        try {
          if (isManufacture) {
            await state.approveReplenishmentManufacture(adjustedRec);
          } else {
            await state.approveRecommendation(adjustedRec);
          }
        } on CloudFunctionException {
          emailsFailed++;
        }
        if (isManufacture) {
          mfgCount++;
        } else {
          purchaseCount++;
        }
      }
      if (!mounted) return;
      final parts = <String>[];
      if (purchaseCount > 0) parts.add('$purchaseCount purchase');
      if (mfgCount > 0) parts.add('$mfgCount manufacturing');
      final failNote = emailsFailed > 0
          ? ' ($emailsFailed email failure${emailsFailed == 1 ? '' : 's'})'
          : '';
      messenger.showSnackBar(SnackBar(
        content: Text('${parts.join(", ")} order(s) approved$failNote'),
        backgroundColor: emailsFailed > 0 ? AppColors.warning : AppColors.success,
      ));
      setState(() {
        _selectedIds.clear();
        _selectAll = false;
      });
      if (mfgCount > 0) {
        navigator.go('/recommendations');
      } else if (purchaseCount > 0) {
        navigator.go('/orders');
      }
    } finally {
      if (mounted) setState(() => _bulkApproving = false);
    }
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

    // Priority sort: Critical → Order Now → Monitor
    if (_sortByPriority) {
      const priority = {'Critical': 0, 'Order Now': 1, 'Monitor': 2};
      recommendations.sort(
        (a, b) => (priority[a.status] ?? 3).compareTo(priority[b.status] ?? 3),
      );
    }

    final supplierMap = {for (final s in state.suppliers) s.id: s};

    final totalSuggested = recommendations.fold<int>(
      0,
      (s, r) => s + (_adjustedQty[r.productId] ?? r.suggestedOrderQty),
    );
    final needingAction = recommendations
        .where((r) => r.status == 'Critical' || r.status == 'Order Now')
        .length;
    final estimatedCost = recommendations.fold<double>(0, (sum, r) {
      final product = productMap[r.productId];
      final qty = _adjustedQty[r.productId] ?? r.suggestedOrderQty;
      return sum + qty * (product?.unitCost ?? 0);
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
                  value: 'EGP ${estimatedCost.toStringAsFixed(0)}',
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
                      const SizedBox(width: 8),
                      Tooltip(
                        message: _sortByPriority
                            ? 'Sorted by priority (Critical first)'
                            : 'Sort by priority',
                        child: FilterChip(
                          label: const Text('Priority'),
                          avatar: const Icon(Icons.sort, size: 14),
                          selected: _sortByPriority,
                          onSelected: (v) =>
                              setState(() => _sortByPriority = v),
                          selectedColor: AppColors.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _exportCsv(context, recommendations, productMap),
                        icon: const Icon(Icons.download),
                        label: const Text('Export'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  if (recommendations.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(
                          value: _selectAll,
                          onChanged: (v) {
                            setState(() {
                              _selectAll = v ?? false;
                              if (_selectAll) {
                                _selectedIds.addAll(
                                  recommendations.map((r) => r.productId),
                                );
                              } else {
                                _selectedIds.clear();
                              }
                            });
                          },
                        ),
                        Text(
                          'Select All (${_selectedIds.length}/${recommendations.length})',
                          style: AppTextStyles.body,
                        ),
                        const Spacer(),
                        if (_selectedIds.isNotEmpty)
                          ElevatedButton.icon(
                            onPressed: _bulkApproving
                                ? null
                                : () => _approveSelected(context, recommendations, productMap),
                            icon: _bulkApproving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.check_circle),
                            label: Text(_bulkApproving
                                ? 'Approving…'
                                : 'Approve ${_selectedIds.length} & Create Order'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ],
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
                      : HorizontallyScrollableTable(
                          child: DataTable(
                            columns: [
                              const DataColumn(label: SizedBox(width: 24)),
                              DataColumn(label: Text('PRODUCT', style: AppTextStyles.tableHeader)),
                              DataColumn(label: Text('TYPE', style: AppTextStyles.tableHeader)),
                              DataColumn(label: Text('STOCK', style: AppTextStyles.tableHeader), numeric: true),
                              DataColumn(label: Text('FORECAST', style: AppTextStyles.tableHeader), numeric: true),
                              DataColumn(label: Text('ROP', style: AppTextStyles.tableHeader), numeric: true),
                              DataColumn(label: Text('ORDER QTY', style: AppTextStyles.tableHeader), numeric: true),
                              DataColumn(label: Text('EST. ARRIVAL', style: AppTextStyles.tableHeader)),
                              DataColumn(label: Text('STATUS', style: AppTextStyles.tableHeader)),
                              DataColumn(label: Text('ACTION', style: AppTextStyles.tableHeader)),
                            ],
                            rows: recommendations.map((r) {
                              final product = productMap[r.productId];
                              final isManufacture = product?.manufacturerId != null &&
                                  product!.manufacturerId!.isNotEmpty;
                              final isSelected = _selectedIds.contains(r.productId);
                              final adjustedVal = _adjustedQty[r.productId] ?? r.suggestedOrderQty;
                              final deviation = r.suggestedOrderQty > 0
                                  ? ((adjustedVal - r.suggestedOrderQty) / r.suggestedOrderQty * 100).round()
                                  : 0;
                              return DataRow(
                                color: AppColors.dataRowColor,
                                selected: isSelected,
                                cells: [
                                  DataCell(
                                    Checkbox(
                                      value: isSelected,
                                      onChanged: (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selectedIds.add(r.productId);
                                          } else {
                                            _selectedIds.remove(r.productId);
                                          }
                                          _selectAll = _selectedIds.length == recommendations.length;
                                        });
                                      },
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: Colors.grey[200],
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Icon(
                                            isManufacture ? Icons.precision_manufacturing : Icons.inventory,
                                            size: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              r.productName,
                                              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                                            ),
                                            Text(r.sku, style: AppTextStyles.label),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Chip(
                                      label: Text(
                                        isManufacture ? 'Manufacture' : 'Purchase',
                                        style: TextStyle(
                                          color: isManufacture ? Colors.deepPurple : AppColors.primary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      backgroundColor: isManufacture
                                          ? Colors.deepPurple.withValues(alpha: 0.1)
                                          : AppColors.primary.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  DataCell(Text('${r.currentStock}')),
                                  DataCell(Text('${r.forecastNextPeriod}')),
                                  DataCell(Text('${r.reorderPoint}')),
                                  DataCell(
                                    SizedBox(
                                      width: 90,
                                      child: TextFormField(
                                        initialValue: '$adjustedVal',
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                          suffixIcon: deviation.abs() > 30
                                              ? Tooltip(
                                                  message: '${deviation > 0 ? "+" : ""}$deviation% from suggestion',
                                                  child: const Icon(Icons.warning_amber, color: AppColors.warning, size: 16),
                                                )
                                              : null,
                                        ),
                                        style: AppTextStyles.body.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                        onChanged: (v) {
                                          final parsed = int.tryParse(v);
                                          if (parsed != null && parsed > 0) {
                                            setState(() {
                                              _adjustedQty[r.productId] = parsed;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  DataCell(_buildArrivalDate(r, product, supplierMap)),
                                  DataCell(StatusChip(r.status)),
                                  DataCell(
                                    _buildApproveButton(context, r, product),
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
