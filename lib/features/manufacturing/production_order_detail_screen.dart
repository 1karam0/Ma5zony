import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/production_order.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class ProductionOrderDetailScreen extends StatefulWidget {
  final String orderId;
  const ProductionOrderDetailScreen({super.key, required this.orderId});

  @override
  State<ProductionOrderDetailScreen> createState() =>
      _ProductionOrderDetailScreenState();
}

class _ProductionOrderDetailScreenState
    extends State<ProductionOrderDetailScreen> {
  bool _logsLoaded = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final order =
        state.productionOrders.where((o) => o.id == widget.orderId).firstOrNull;

    if (order == null) {
      return const Center(child: Text('Order not found'));
    }

    // Auto-load workflow logs on first build
    if (!_logsLoaded) {
      _logsLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        state.loadWorkflowLogs(
          entityType: 'ProductionOrder',
          entityId: widget.orderId,
        );
      });
    }

    final products = {for (final p in state.products) p.id: p.name};
    final manufacturers = {for (final m in state.manufacturers) m.id: m.name};
    final rawMaterials = {for (final m in state.rawMaterials) m.id: m};

    // Find linked raw material orders
    final rmOrders = state.rawMaterialOrders
        .where((o) => o.productionOrderId == order.id)
        .toList();

    // Find linked workflow logs
    final logs = state.workflowLogs
        .where((l) => l.entityId == order.id)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Production Order — ${products[order.finalProductId] ?? 'Unknown'}',
                  style: AppTextStyles.h2,
                ),
              ),
              _StatusChip(status: order.status),
            ],
          ),
          const SizedBox(height: 24),

          // Order details card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(title: 'Order Details'),
                  Wrap(
                    spacing: 32,
                    runSpacing: 16,
                    children: [
                      _DetailItem(
                          label: 'Product',
                          value:
                              products[order.finalProductId] ?? 'Unknown'),
                      _DetailItem(
                          label: 'Quantity',
                          value: '${order.quantity} units'),
                      _DetailItem(
                          label: 'Manufacturer',
                          value: manufacturers[order.manufacturerId] ??
                              'Unassigned'),
                      _DetailItem(
                          label: 'Est. Cost',
                          value:
                              '\$${order.estimatedCost.toStringAsFixed(2)}'),
                      _DetailItem(
                          label: 'Created',
                          value: _formatDate(order.createdAt)),
                      if (order.estimatedCompletionDate != null)
                        _DetailItem(
                            label: 'Est. Completion',
                            value: _formatDate(
                                order.estimatedCompletionDate!)),
                      if (order.completedAt != null)
                        _DetailItem(
                            label: 'Completed',
                            value: _formatDate(order.completedAt!)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Action buttons
                  _ActionButtons(order: order, state: state),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Raw Material Orders
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(title: 'Raw Material Orders'),
                  if (rmOrders.isEmpty)
                    const Text('No material orders linked.',
                        style: TextStyle(color: AppColors.textSecondary))
                  else
                    DataTable(
                      columns: const [
                        DataColumn(label: Text('Material')),
                        DataColumn(label: Text('Quantity')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Requested')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: rmOrders.map((rmo) {
                        final rm = rawMaterials[rmo.rawMaterialId];
                        return DataRow(cells: [
                          DataCell(Text(rm?.name ?? rmo.rawMaterialId)),
                          DataCell(Text('${rmo.quantity} ${rm?.unit ?? ''}')),
                          DataCell(_RMStatusChip(status: rmo.status)),
                          DataCell(Text(_formatDate(rmo.requestedDate))),
                          DataCell(
                            rmo.status == 'completed'
                                ? const Text('—')
                                : PopupMenuButton<String>(
                                    tooltip: 'Update Status',
                                    onSelected: (newStatus) async {
                                      try {
                                        await state
                                            .updateRawMaterialOrderStatus(
                                                rmo, newStatus);
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text('Error: $e')),
                                          );
                                        }
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      if (rmo.status == 'pending')
                                        const PopupMenuItem(
                                            value: 'accepted',
                                            child: Text('Mark Accepted')),
                                      if (rmo.status == 'accepted')
                                        const PopupMenuItem(
                                            value: 'in_progress',
                                            child: Text('Mark In Progress')),
                                      if (rmo.status == 'in_progress')
                                        const PopupMenuItem(
                                            value: 'completed',
                                            child: Text('Mark Completed')),
                                    ],
                                  ),
                          ),
                        ]);
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Workflow Log
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: 'Workflow Log',
                    actions: [
                      TextButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Refresh'),
                        onPressed: () => state.loadWorkflowLogs(
                          entityType: 'productionOrder',
                          entityId: order.id,
                        ),
                      ),
                    ],
                  ),
                  if (logs.isEmpty)
                    const Text('No log entries.',
                        style: TextStyle(color: AppColors.textSecondary))
                  else
                    ...logs.map((log) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.history, size: 18),
                          title: Text(log.action),
                          subtitle: Text(
                            '${_formatDateTime(log.timestamp)} • ${log.performedBy}',
                            style: AppTextStyles.bodySmall,
                          ),
                          trailing: log.details != null
                              ? Tooltip(
                                  message: log.details!,
                                  child: const Icon(Icons.info_outline,
                                      size: 16),
                                )
                              : null,
                        )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatDateTime(DateTime d) =>
      '${_formatDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _ActionButtons extends StatelessWidget {
  final ProductionOrder order;
  final AppState state;
  const _ActionButtons({required this.order, required this.state});

  @override
  Widget build(BuildContext context) {
    final nextStatus = _nextStatus(order.status);
    if (nextStatus == null) return const SizedBox.shrink();

    return ElevatedButton.icon(
      icon: const Icon(Icons.arrow_forward, size: 18),
      label: Text('Advance to ${_statusLabel(nextStatus)}'),
      onPressed: () async {
        try {
          await state.updateProductionOrderStatus(order, nextStatus);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text('Status updated to ${_statusLabel(nextStatus)}')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        }
      },
    );
  }

  ProductionOrderStatus? _nextStatus(ProductionOrderStatus current) =>
      switch (current) {
        ProductionOrderStatus.draft => ProductionOrderStatus.approved,
        ProductionOrderStatus.materialsReady =>
          ProductionOrderStatus.inProduction,
        ProductionOrderStatus.inProduction =>
          ProductionOrderStatus.completed,
        _ => null, // Other transitions are automated
      };

  String _statusLabel(ProductionOrderStatus s) => switch (s) {
        ProductionOrderStatus.draft => 'Draft',
        ProductionOrderStatus.approved => 'Approved',
        ProductionOrderStatus.materialsOrdered => 'Materials Ordered',
        ProductionOrderStatus.materialsReady => 'Materials Ready',
        ProductionOrderStatus.inProduction => 'In Production',
        ProductionOrderStatus.completed => 'Completed',
      };
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
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide.none,
    );
  }
}

class _RMStatusChip extends StatelessWidget {
  final String status;
  const _RMStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'pending' => AppColors.textSecondary,
      'accepted' => AppColors.primary,
      'in_progress' => AppColors.warning,
      'completed' => AppColors.success,
      _ => AppColors.textSecondary,
    };
    final label = switch (status) {
      'pending' => 'Pending',
      'accepted' => 'Accepted',
      'in_progress' => 'In Progress',
      'completed' => 'Completed',
      _ => status,
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

class _DetailItem extends StatelessWidget {
  final String label;
  final String value;
  const _DetailItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: 2),
        Text(value, style: AppTextStyles.body),
      ],
    );
  }
}
