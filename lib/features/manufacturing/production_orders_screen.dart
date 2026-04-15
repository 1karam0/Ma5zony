import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/production_order.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class ProductionOrdersScreen extends StatefulWidget {
  const ProductionOrdersScreen({super.key});

  @override
  State<ProductionOrdersScreen> createState() =>
      _ProductionOrdersScreenState();
}

class _ProductionOrdersScreenState extends State<ProductionOrdersScreen> {
  ProductionOrderStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final products = {for (final p in state.products) p.id: p.name};
    final manufacturers = {for (final m in state.manufacturers) m.id: m.name};

    var orders = state.productionOrders.toList();
    if (_statusFilter != null) {
      orders = orders.where((o) => o.status == _statusFilter).toList();
    }
    orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // KPIs
    final active = state.productionOrders
        .where((o) =>
            o.status != ProductionOrderStatus.completed &&
            o.status != ProductionOrderStatus.draft)
        .length;
    final totalCost = state.productionOrders
        .where((o) => o.status != ProductionOrderStatus.completed)
        .fold<double>(0, (s, o) => s + o.estimatedCost);

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Production Orders'),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 200,
                child: KPICard(
                  title: 'Total Orders',
                  value: '${state.productionOrders.length}',
                  icon: Icons.factory,
                ),
              ),
              SizedBox(
                width: 200,
                child: KPICard(
                  title: 'Active',
                  value: '$active',
                  icon: Icons.play_circle,
                  color: AppColors.accent,
                ),
              ),
              SizedBox(
                width: 200,
                child: KPICard(
                  title: 'Open Cost',
                  value: '\$${totalCost.toStringAsFixed(0)}',
                  icon: Icons.attach_money,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Status filter
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _statusFilter == null,
                onSelected: (_) => setState(() => _statusFilter = null),
              ),
              for (final status in ProductionOrderStatus.values)
                ChoiceChip(
                  label: Text(_statusLabel(status)),
                  selected: _statusFilter == status,
                  onSelected: (sel) =>
                      setState(() => _statusFilter = sel ? status : null),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('Qty')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Manufacturer')),
                  DataColumn(label: Text('Cost')),
                  DataColumn(label: Text('Created')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: orders.map((o) {
                  return DataRow(cells: [
                    DataCell(Text(products[o.finalProductId] ?? '—')),
                    DataCell(Text('${o.quantity}')),
                    DataCell(_StatusChip(status: o.status)),
                    DataCell(
                        Text(manufacturers[o.manufacturerId] ?? '—')),
                    DataCell(Text(
                        '\$${o.estimatedCost.toStringAsFixed(0)}')),
                    DataCell(Text(_formatDate(o.createdAt))),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.visibility, size: 18),
                          tooltip: 'Details',
                          onPressed: () =>
                              context.go('/production-orders/${o.id}'),
                        ),
                        if (o.status == ProductionOrderStatus.draft)
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: Colors.red),
                            tooltip: 'Delete',
                            onPressed: () => _confirmDelete(context, state, o),
                          ),
                        if (o.status != ProductionOrderStatus.draft &&
                            o.status != ProductionOrderStatus.completed)
                          IconButton(
                            icon: const Icon(Icons.cancel_outlined,
                                size: 18, color: Colors.orange),
                            tooltip: 'Cancel',
                            onPressed: () => _confirmCancel(context, state, o),
                          ),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
          if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 48, color: AppColors.textSecondary),
                    SizedBox(height: 8),
                    Text('No production orders yet',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(ProductionOrderStatus s) => switch (s) {
        ProductionOrderStatus.draft => 'Draft',
        ProductionOrderStatus.approved => 'Approved',
        ProductionOrderStatus.materialsOrdered => 'Materials Ordered',
        ProductionOrderStatus.materialsReady => 'Materials Ready',
        ProductionOrderStatus.inProduction => 'In Production',
        ProductionOrderStatus.completed => 'Completed',
      };

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _confirmDelete(
      BuildContext context, AppState state, ProductionOrder o) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Draft Order?'),
        content: const Text('This will permanently delete the draft order.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await state.deleteProductionOrder(o.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft order deleted')),
        );
      }
    }
  }

  Future<void> _confirmCancel(
      BuildContext context, AppState state, ProductionOrder o) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: const Text(
            'This will cancel the production order. This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('Cancel Order')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await state.cancelProductionOrder(o.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled')),
        );
      }
    }
  }
}

class _StatusChip extends StatelessWidget {
  final ProductionOrderStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ProductionOrderStatus.draft => ('Draft', AppColors.textSecondary),
      ProductionOrderStatus.approved => ('Approved', AppColors.primary),
      ProductionOrderStatus.materialsOrdered =>
        ('Materials Ordered', AppColors.warning),
      ProductionOrderStatus.materialsReady =>
        ('Materials Ready', AppColors.accent),
      ProductionOrderStatus.inProduction =>
        ('In Production', Colors.deepPurple),
      ProductionOrderStatus.completed => ('Completed', AppColors.success),
    };
    return Chip(
      label: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}
