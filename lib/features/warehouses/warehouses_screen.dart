import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class WarehousesScreen extends StatelessWidget {
  const WarehousesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final warehouses = state.warehouses;
    final products = state.products;

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalStock = warehouses.fold<int>(0, (sum, w) => sum + w.totalStock);
    final totalValue = state.totalStockValue;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI row
          Row(
            children: [
              Expanded(
                child: KPICard(
                  title: 'Total Facilities',
                  value: '${warehouses.length}',
                  icon: Icons.warehouse,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Total Units Stored',
                  value: '$totalStock',
                  icon: Icons.inventory_2,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Total Stock Value',
                  value: '\$${totalValue.toStringAsFixed(0)}',
                  icon: Icons.monetization_on,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Low Stock Alerts',
                  value: '${state.lowStockItems}',
                  icon: Icons.warning,
                  color: AppColors.warning,
                  isAlert: state.lowStockItems > 0,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          SectionHeader(
            title: 'Warehouses',
            actions: [
              ElevatedButton.icon(
                onPressed: () => _showAddWarehouseDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Warehouse'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Warehouse Name')),
                  DataColumn(label: Text('Location')),
                  DataColumn(label: Text('Total Stock')),
                  DataColumn(label: Text('SKUs Stored')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: warehouses.map((w) {
                  final skuCount = products
                      .where((p) => p.warehouseId == w.id)
                      .length;
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          w.name,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      DataCell(Text('${w.city}, ${w.country}')),
                      DataCell(Text('${w.totalStock} units')),
                      DataCell(Text('$skuCount SKUs')),
                      const DataCell(StatusChip('Active')),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () {},
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                size: 20,
                                color: AppColors.error,
                              ),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Deleted warehouse: ${w.name}',
                                    ),
                                  ),
                                );
                              },
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Per-warehouse product breakdown
          ...warehouses.map((w) {
            final wProducts = products
                .where((p) => p.warehouseId == w.id)
                .toList();
            if (wProducts.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${w.name} — Product Breakdown', style: AppTextStyles.h3),
                const SizedBox(height: 12),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('SKU')),
                        DataColumn(label: Text('Product')),
                        DataColumn(label: Text('Category')),
                        DataColumn(label: Text('Stock')),
                      ],
                      rows: wProducts.map((p) {
                        return DataRow(
                          cells: [
                            DataCell(Text(p.sku)),
                            DataCell(Text(p.name)),
                            DataCell(Text(p.category)),
                            DataCell(Text('${p.currentStock}')),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          }),
        ],
      ),
    );
  }

  void _showAddWarehouseDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final countryCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Warehouse'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Warehouse Name'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: cityCtrl,
                      decoration: const InputDecoration(labelText: 'City'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: countryCtrl,
                      decoration: const InputDecoration(labelText: 'Country'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Warehouse "${nameCtrl.text}" added')),
              );
            },
            child: const Text('Add Warehouse'),
          ),
        ],
      ),
    );
  }
}
