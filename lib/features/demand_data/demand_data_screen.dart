import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class DemandDataScreen extends StatelessWidget {
  const DemandDataScreen({super.key});

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
                      onPressed: () {},
                      icon: const Icon(Icons.file_upload),
                      label: const Text('Import CSV'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () {},
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

class _DemandHistoryTab extends StatelessWidget {
  const _DemandHistoryTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final productMap = {for (final p in state.products) p.id: p.name};

    // Flatten demand history into a sorted list
    final allRecords =
        state.demandByProduct.values.expand((list) => list).toList()
          ..sort((a, b) => b.periodStart.compareTo(a.periodStart));

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
              const Expanded(
                child: KPICard(
                  title: 'Top Sales Source',
                  value: 'Internal',
                  icon: Icons.store,
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
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Period')),
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('Quantity')),
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
              final warehouse = state.warehouses.firstWhere(
                (w) => w.id == p.warehouseId,
                orElse: () => state.warehouses.isNotEmpty
                    ? state.warehouses.first
                    : throw StateError('No warehouses'),
              );
              return DataRow(
                cells: [
                  DataCell(Text(p.sku)),
                  DataCell(Text(p.name)),
                  DataCell(Text(p.category)),
                  DataCell(Text('${p.currentStock}')),
                  DataCell(Text('\$${p.unitCost.toStringAsFixed(2)}')),
                  DataCell(Text(warehouse.name)),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
