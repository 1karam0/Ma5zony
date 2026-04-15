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

class _ActionButtons extends StatefulWidget {
  final ProductionOrder order;
  final AppState state;
  const _ActionButtons({required this.order, required this.state});

  @override
  State<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends State<_ActionButtons> {
  bool _advancing = false;

  @override
  Widget build(BuildContext context) {
    final nextStatus = _nextStatus(widget.order.status);
    if (nextStatus == null) {
      if (widget.order.status == ProductionOrderStatus.completed) {
        return Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success),
            const SizedBox(width: 8),
            Text('Production complete — stock updated',
                style: AppTextStyles.body.copyWith(color: AppColors.success)),
          ],
        );
      }
      return const SizedBox.shrink();
    }

    final isStart = nextStatus == ProductionOrderStatus.inProduction;
    final isComplete = nextStatus == ProductionOrderStatus.completed;

    return ElevatedButton.icon(
      icon: _advancing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Icon(isComplete ? Icons.check_circle : Icons.arrow_forward, size: 18),
      label: Text(_advancing ? 'Updating...' : 'Advance to ${_statusLabel(nextStatus)}'),
      style: isComplete
          ? ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            )
          : isStart
              ? ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                )
              : null,
      onPressed: _advancing ? null : () => _onAdvance(context, nextStatus),
    );
  }

  Future<void> _onAdvance(BuildContext context, ProductionOrderStatus nextStatus) async {
    final order = widget.order;
    final state = widget.state;

    // Confirmation dialog for starting production
    if (nextStatus == ProductionOrderStatus.inProduction) {
      final rmOrders = state.rawMaterialOrders
          .where((o) => o.productionOrderId == order.id)
          .toList();
      final materialLines = rmOrders.map((rmo) {
        final rm = state.rawMaterials.where((r) => r.id == rmo.rawMaterialId).firstOrNull;
        return '• ${rm?.name ?? rmo.rawMaterialId}: −${rmo.quantity} ${rm?.unit ?? "units"}';
      }).join('\n');

      final productName = state.products
          .where((p) => p.id == order.finalProductId)
          .firstOrNull
          ?.name ?? 'Unknown';
      final mfgName = state.manufacturers
          .where((m) => m.id == order.manufacturerId)
          .firstOrNull
          ?.name ?? 'Unknown';

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start Production?'),
          content: Text(
            'This will:\n\n'
            '1. Deduct raw materials from stock:\n$materialLines\n\n'
            '2. Send an email to manufacturer: $mfgName\n\n'
            '3. Start production for ${order.quantity} units of $productName',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
              child: const Text('Start Production'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    // Confirmation dialog for completing production
    if (nextStatus == ProductionOrderStatus.completed) {
      final productName = state.products
          .where((p) => p.id == order.finalProductId)
          .firstOrNull
          ?.name ?? 'Unknown';

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mark as Complete?'),
          content: Text(
            'This will add ${order.quantity} units to "$productName" inventory.\n\n'
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
              child: const Text('Complete Production'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _advancing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.updateProductionOrderStatus(order, nextStatus);
      if (mounted) {
        final extra = nextStatus == ProductionOrderStatus.inProduction
            ? ' — email sent to manufacturer'
            : nextStatus == ProductionOrderStatus.completed
                ? ' — stock updated'
                : '';
        messenger.showSnackBar(
          SnackBar(content: Text('Status updated to ${_statusLabel(nextStatus)}$extra')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  ProductionOrderStatus? _nextStatus(ProductionOrderStatus current) =>
      switch (current) {
        ProductionOrderStatus.draft => ProductionOrderStatus.approved,
        ProductionOrderStatus.materialsReady =>
          ProductionOrderStatus.inProduction,
        ProductionOrderStatus.inProduction =>
          ProductionOrderStatus.completed,
        _ => null,
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
