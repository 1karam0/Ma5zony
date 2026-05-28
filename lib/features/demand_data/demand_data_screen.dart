import 'package:csv/csv.dart' show CsvDecoder;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/features/onboarding/tour_targets.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';
import 'package:ma5zony/widgets/zoho_patterns.dart';

class DemandDataScreen extends StatelessWidget {
  const DemandDataScreen({super.key});

  Future<void> _importCsv(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    if (!context.mounted) return;

    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);

    final content = String.fromCharCodes(result.files.single.bytes!);
    final rows = const CsvDecoder().convert(content);

    // Expect header (case-insensitive). Accepted column 0 names:
    //   productId | sku | product | name
    // Accepted column 1 names: periodStart | date | month
    // Accepted column 2 names: quantity | qty | units
    if (rows.length < 2) {
      messenger.showSnackBar(const SnackBar(
        content: Text('CSV is empty or missing data rows.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ));
      return;
    }

    // Build lookup indexes for resolving the product identifier the user
    // provided in column 0. We try (in order): exact id, exact sku, name.
    final products = state.products;
    final byId = {for (final p in products) p.id.toLowerCase(): p};
    final bySku = {
      for (final p in products)
        if (p.sku.isNotEmpty) p.sku.toLowerCase(): p
    };
    final byName = {for (final p in products) p.name.toLowerCase(): p};

    final records = <DomainDemandRecord>[];
    final unresolved = <String>{};
    var skippedRows = 0;

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) {
        skippedRows++;
        continue;
      }
      final rawKey = row[0].toString().trim();
      final dateStr = row[1].toString().trim();
      final qty = int.tryParse(row[2].toString().trim()) ?? 0;
      final date = DateTime.tryParse(dateStr);
      if (date == null || rawKey.isEmpty || qty <= 0) {
        skippedRows++;
        continue;
      }

      final key = rawKey.toLowerCase();
      final product = byId[key] ?? bySku[key] ?? byName[key];
      if (product == null) {
        unresolved.add(rawKey);
        continue;
      }

      records.add(DomainDemandRecord(
        id: '',
        productId: product.id, // ALWAYS resolved to the Firestore product id
        periodStart: date,
        quantity: qty,
      ));
    }

    if (records.isEmpty) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import failed'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No demand records were imported.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text('Expected CSV columns (header row required):'),
                const SizedBox(height: 4),
                const Text(
                  '  1. Product (id, SKU, or name)\n'
                  '  2. periodStart (yyyy-MM-dd)\n'
                  '  3. quantity (positive integer)',
                  style: TextStyle(fontFamily: 'monospace'),
                ),
                if (unresolved.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${unresolved.length} product identifier(s) could not be matched to any product in your catalog:',
                  ),
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 160),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        unresolved.take(20).join(', ') +
                            (unresolved.length > 20 ? ' …' : ''),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tip: add these products to your catalog first, or use their existing SKU / name exactly as it appears in Products.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
          ],
        ),
      );
      return;
    }

    await state.addDemandRecordsBatch(records);
    if (!context.mounted) return;

    final parts = <String>['${records.length} record(s) imported'];
    if (unresolved.isNotEmpty) {
      parts.add('${unresolved.length} unmatched product(s) skipped');
    }
    if (skippedRows > 0) parts.add('$skippedRows invalid row(s) skipped');

    messenger.showSnackBar(SnackBar(
      content: Text(parts.join(' · ')),
      backgroundColor:
          unresolved.isEmpty && skippedRows == 0 ? AppColors.success : null,
      duration: const Duration(seconds: 6),
      action: unresolved.isNotEmpty
          ? SnackBarAction(
              label: 'Details',
              textColor: Colors.white,
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Unmatched product identifiers'),
                    content: SizedBox(
                      width: 400,
                      child: SingleChildScrollView(
                        child: Text(unresolved.join('\n')),
                      ),
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Close')),
                    ],
                  ),
                );
              },
            )
          : null,
    ));
  }

  void _showAddRecordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _AddDemandRecordDialog(),
    );
  }

  Future<void> _importShopifyOrders(BuildContext context) async {
    final state = context.read<AppState>();
    if (state.shopifyConnection?.isConnected != true) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Shopify Not Connected'),
          content: const Text(
            'Connect your Shopify store to automatically pull order history as demand records. '
            'This lets the system build accurate forecasts from real sales data.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/integrations');
              },
              child: const Text('Connect Shopify'),
            ),
          ],
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Importing Shopify order history…'),
      duration: Duration(seconds: 60),
    ));
    try {
      final result = await state.importShopifyOrders();
      messenger.clearSnackBars();
      if (context.mounted) {
        final imported = result?['newRecordsImported'] as int? ?? 0;
        messenger.showSnackBar(SnackBar(
          content: Text(imported > 0
              ? '$imported demand records imported from Shopify orders.'
              : 'No new orders found to import.'),
          backgroundColor: imported > 0 ? AppColors.success : null,
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (e) {
      messenger.clearSnackBars();
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isShopifyConnected = state.shopifyConnection?.isConnected == true;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: 'Demand and Inventory Data Logs',
                  actions: [
                    OutlinedButton.icon(
                      onPressed: () => _importShopifyOrders(context),
                      icon: Icon(Icons.sync, size: 16, color: isShopifyConnected ? Colors.green[700] : AppColors.textSecondary),
                      label: Text(
                        'Import Shopify Orders',
                        style: TextStyle(color: isShopifyConnected ? Colors.green[700] : AppColors.textSecondary),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: isShopifyConnected ? Colors.green[400]! : AppColors.border),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => _importCsv(context),
                      icon: const Icon(Icons.file_upload),
                      label: const Tooltip(
                        message:
                            'CSV columns: product (id, SKU, or name), periodStart (yyyy-MM-dd), quantity',
                        child: Text('Import CSV'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    KeyedSubtree(
                      key: TourTargets.instance.keyFor('page:demand.add'),
                      child: ElevatedButton.icon(
                        onPressed: () => _showAddRecordDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Demand Record'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const TabBar(
                  tabs: [
                    Tab(text: 'Demand History'),
                    Tab(text: 'Inventory Records'),
                  ],
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                ),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [_DemandHistoryTab(), _InventoryRecordsTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _DemandHistoryTab extends StatefulWidget {
  const _DemandHistoryTab();

  @override
  State<_DemandHistoryTab> createState() => _DemandHistoryTabState();
}

class _DemandHistoryTabState extends State<_DemandHistoryTab> {
  String _sourceFilter = 'All'; // 'All', 'manual', 'shopify'

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final productMap = {for (final p in state.products) p.id: p.name};

    // Flatten demand history into a sorted list
    var allRecords =
        state.demandByProduct.values.expand((list) => list).toList()
          ..sort((a, b) => b.periodStart.compareTo(a.periodStart));

    // Apply source filter
    if (_sourceFilter != 'All') {
      allRecords =
          allRecords.where((r) => r.source == _sourceFilter).toList();
    }

    final totalDemand30d = state.demandByProduct.values
        .expand((list) => list)
        .where(
          (r) => r.periodStart.isAfter(
            DateTime.now().subtract(const Duration(days: 30)),
          ),
        )
        .fold<int>(0, (sum, r) => sum + r.quantity);

    final productsWithDemand = state.demandByProduct.keys.length;

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
                  title: 'Total Demand (30D)',
                  value: '$totalDemand30d',
                  icon: Icons.trending_up,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Products with Demand',
                  value: '$productsWithDemand',
                  icon: Icons.category,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Total Records',
                  value: '${allRecords.length}',
                  icon: Icons.storage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Source filter chips
          Row(
            children: [
              const Text('Source: '),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('All'),
                selected: _sourceFilter == 'All',
                onSelected: (_) => setState(() => _sourceFilter = 'All'),
                selectedColor: AppColors.primary.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Manual'),
                selected: _sourceFilter == 'manual',
                onSelected: (_) => setState(() => _sourceFilter = 'manual'),
                selectedColor: AppColors.primary.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Shopify'),
                selected: _sourceFilter == 'shopify',
                onSelected: (_) => setState(() => _sourceFilter = 'shopify'),
                selectedColor: Colors.green.withValues(alpha: 0.2),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (allRecords.isEmpty)
            _DemandEmptyState(
              isFiltered: _sourceFilter != 'All',
              isShopifyConnected: state.shopifyConnection?.isConnected == true,
            )
          else
            Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Period')),
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('Quantity')),
                  DataColumn(label: Text('Source')),
                  DataColumn(label: Text('Status')),
                ],
                rows: allRecords.take(60).map((d) {
                  final productName = productMap[d.productId] ?? d.productId;
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(DateFormat('MMM yyyy').format(d.periodStart)),
                      ),
                      DataCell(Text(productName)),
                      DataCell(Text('${d.quantity}')),
                      DataCell(StatusChip(
                        d.source == 'shopify' ? 'Shopify' : 'Manual',
                      )),
                      const DataCell(StatusChip('OK')),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryRecordsTab extends StatelessWidget {
  const _InventoryRecordsTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final products = state.products;

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: double.infinity,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('SKU')),
              DataColumn(label: Text('Product')),
              DataColumn(label: Text('Category')),
              DataColumn(label: Text('Current Stock')),
              DataColumn(label: Text('Unit Cost')),
              DataColumn(label: Text('Warehouse')),
            ],
            rows: products.map((p) {
              final warehouseName = state.warehouses.isEmpty
                  ? '—'
                  : (state.warehouses.any((w) => w.id == p.warehouseId)
                      ? state.warehouses.firstWhere((w) => w.id == p.warehouseId).name
                      : state.warehouses.first.name);
              return DataRow(
                cells: [
                  DataCell(Text(p.sku)),
                  DataCell(Text(p.name)),
                  DataCell(Text(p.category)),
                  DataCell(Text('${p.currentStock}')),
                  DataCell(Text('EGP ${p.unitCost.toStringAsFixed(2)}')),
                  DataCell(Text(warehouseName)),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ─── Demand Empty State ───────────────────────────────────────────────────────

class _DemandEmptyState extends StatelessWidget {
  const _DemandEmptyState({
    required this.isFiltered,
    required this.isShopifyConnected,
  });

  final bool isFiltered;
  final bool isShopifyConnected;

  @override
  Widget build(BuildContext context) {
    if (isFiltered) {
      return const EmptyStateWidget(
        icon: Icons.filter_list_off,
        title: 'No matching records',
        description: 'Try changing the source filter to see all demand records.',
      );
    }

    if (!isShopifyConnected) {
      return EmptyStateWidget(
        icon: Icons.show_chart,
        title: 'No demand data yet',
        description:
            'Connect your Shopify store to automatically import sales history, '
            'or add records manually.',
        primaryLabel: 'Connect Shopify',
        onPrimary: () => context.go('/integrations'),
        secondaryLabel: 'Add Manually',
        onSecondary: () => showDialog(
          context: context,
          builder: (_) => const _AddDemandRecordDialog(),
        ),
      );
    }

    return EmptyStateWidget(
      icon: Icons.show_chart,
      title: 'No demand records yet',
      description:
          'Import a CSV or add records manually. Your Shopify store will '
          'also sync sales here automatically.',
      primaryLabel: 'Add Record',
      onPrimary: () => showDialog(
        context: context,
        builder: (_) => const _AddDemandRecordDialog(),
      ),
    );
  }
}

// ─── Add Demand Record Dialog ─────────────────────────────────────────────────

class _AddDemandRecordDialog extends StatefulWidget {
  const _AddDemandRecordDialog();

  @override
  State<_AddDemandRecordDialog> createState() => _AddDemandRecordDialogState();
}

class _AddDemandRecordDialogState extends State<_AddDemandRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedProductId;
  final _qtyCtrl = TextEditingController();
  DateTime _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = context.read<AppState>().products;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.show_chart,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add Demand Record', style: AppTextStyles.h3),
                const SizedBox(height: 2),
                Text(
                  'Historical sales feed the forecasting engine.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.textSecondary,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ZohoFormSection(
                  title: 'Record Details',
                  subtitle:
                      'Pick a product, units sold, and the month this represents.',
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Product *',
                      ),
                      initialValue: _selectedProductId,
                      items: products
                          .map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.name,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selectedProductId = v),
                      validator: (v) =>
                          v == null ? 'Select a product' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _qtyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Quantity Sold *',
                        suffixText: 'units',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Quantity is required';
                        }
                        final val = int.tryParse(v);
                        if (val == null || val <= 0) {
                          return 'Enter a positive number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => _selectedDate = DateTime(
                              picked.year, picked.month, 1));
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Period (Month)',
                          prefixIcon: Icon(Icons.calendar_today, size: 18),
                        ),
                        child: Text(
                          DateFormat('MMMM yyyy').format(_selectedDate),
                          style: AppTextStyles.body,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: _selectedProductId == null
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;
                  final record = DomainDemandRecord(
                    id: '',
                    productId: _selectedProductId!,
                    periodStart: _selectedDate,
                    quantity: int.parse(_qtyCtrl.text),
                  );
                  final appState = context.read<AppState>();
                  final messenger = ScaffoldMessenger.of(context);
                  final nav = Navigator.of(context);
                  try {
                    await appState.addDemandRecord(record);
                    nav.pop();
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(
                          content: Text('Failed to add record: $e'),
                          backgroundColor: Colors.red),
                    );
                  }
                },
          child: const Text('Add Record'),
        ),
      ],
    );
  }
}
