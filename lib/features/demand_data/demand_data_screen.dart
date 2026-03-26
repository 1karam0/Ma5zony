import 'package:csv/csv.dart' show CsvDecoder;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

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

    final content = String.fromCharCodes(result.files.single.bytes!);
    final rows = const CsvDecoder().convert(content);

    // Expect header: productId, periodStart (yyyy-MM-dd), quantity
    if (rows.length < 2) return;

    final records = <DomainDemandRecord>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) continue;
      final productId = row[0].toString().trim();
      final dateStr = row[1].toString().trim();
      final qty = int.tryParse(row[2].toString().trim()) ?? 0;
      final date = DateTime.tryParse(dateStr);
      if (date == null || productId.isEmpty || qty <= 0) continue;
      records.add(DomainDemandRecord(
        id: '',
        productId: productId,
        periodStart: date,
        quantity: qty,
      ));
    }

    if (records.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid records found in CSV')),
        );
      }
      return;
    }

    await context.read<AppState>().addDemandRecordsBatch(records);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${records.length} record(s) imported')),
      );
    }
  }

  void _showAddRecordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _AddDemandRecordDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      onPressed: () => _importCsv(context),
                      icon: const Icon(Icons.file_upload),
                      label: const Text('Import CSV'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _showAddRecordDialog(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Record'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
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
                selectedColor: AppColors.primary.withOpacity(0.2),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Manual'),
                selected: _sourceFilter == 'manual',
                onSelected: (_) => setState(() => _sourceFilter = 'manual'),
                selectedColor: AppColors.primary.withOpacity(0.2),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Shopify'),
                selected: _sourceFilter == 'shopify',
                onSelected: (_) => setState(() => _sourceFilter = 'shopify'),
                selectedColor: Colors.green.withOpacity(0.2),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (allRecords.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.show_chart, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No demand records yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
                    SizedBox(height: 8),
                    Text('Add a demand record or import from Shopify.', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
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
                  DataCell(Text('\$${p.unitCost.toStringAsFixed(2)}')),
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
      title: const Text('Add Demand Record'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Product',
                  border: OutlineInputBorder(),
                ),
                value: _selectedProductId,
                items: products
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedProductId = v),
                validator: (v) => v == null ? 'Select a product' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _qtyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Quantity is required';
                  final val = int.tryParse(v);
                  if (val == null || val <= 0) return 'Enter a positive number';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Period Start'),
                subtitle: Text(DateFormat('MMM yyyy').format(_selectedDate)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = DateTime(picked.year, picked.month, 1));
                  }
                },
              ),
            ],
          ),
        ),
      ),
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
                  Navigator.pop(context);
                  await appState.addDemandRecord(record);
                },
          child: const Text('Add Record'),
        ),
      ],
    );
  }
}
