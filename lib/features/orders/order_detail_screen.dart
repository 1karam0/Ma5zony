// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/purchase_order.dart';
import 'package:ma5zony/models/supplier_order.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _sendingEmails = false;

  Future<void> _sendEmails() async {
    setState(() => _sendingEmails = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final appState = context.read<AppState>();
      await appState.markOrderSent(widget.orderId);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Order marked as sent. Supplier emails will be dispatched.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _sendingEmails = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final order = state.purchaseOrders
        .where((o) => o.id == widget.orderId)
        .firstOrNull;

    if (order == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            const Text('Order not found.'),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.go('/orders'),
              child: const Text('Back to Orders'),
            ),
          ],
        ),
      );
    }

    final supplierOrders = state.getSupplierOrdersFor(order.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                onPressed: () => context.go('/orders'),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #${order.id.substring(0, order.id.length > 8 ? 8 : order.id.length).toUpperCase()}',
                      style: AppTextStyles.h3,
                    ),
                    Text(
                      'Created ${DateFormat.yMMMd().add_jm().format(order.createdAt)} by ${order.createdByName}',
                      style: AppTextStyles.label,
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(order.status),
            ],
          ),

          const SizedBox(height: 24),

          // Summary cards
          Row(
            children: [
              Expanded(
                child: KPICard(
                  title: 'Total Items',
                  value: '${order.totalItems}',
                  icon: Icons.inventory,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Total Units',
                  value: '${order.totalQuantity}',
                  icon: Icons.shopping_bag,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Estimated Cost',
                  value: '\$${order.totalEstimatedCost.toStringAsFixed(2)}',
                  icon: Icons.attach_money,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Suppliers',
                  value: '${supplierOrders.length}',
                  icon: Icons.local_shipping,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Action: Send to suppliers
          if (order.status == OrderStatus.confirmed)
            Card(
              color: Colors.blue.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.email, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ready to send to suppliers',
                            style: AppTextStyles.body
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'Email notifications will be sent to ${supplierOrders.length} supplier(s) '
                            'with their respective order details and a link to respond.',
                            style: AppTextStyles.label,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _sendingEmails ? null : _sendEmails,
                      icon: _sendingEmails
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send),
                      label: Text(
                          _sendingEmails ? 'Sending...' : 'Send to Suppliers'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Order items table
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
                  Text('Order Items',
                      style:
                          AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Product')),
                        DataColumn(label: Text('SKU')),
                        DataColumn(label: Text('Supplier')),
                        DataColumn(label: Text('Qty')),
                        DataColumn(label: Text('Unit Cost')),
                        DataColumn(label: Text('Line Total')),
                      ],
                      rows: order.items.map((item) {
                        return DataRow(cells: [
                          DataCell(Text(item.productName)),
                          DataCell(Text(item.sku)),
                          DataCell(Text(item.supplierName ?? 'Unassigned')),
                          DataCell(Text('${item.quantity}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold))),
                          DataCell(
                              Text('\$${item.unitCost.toStringAsFixed(2)}')),
                          DataCell(Text(
                            '\$${item.estimatedCost.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Supplier order status
          if (supplierOrders.isNotEmpty) ...[
            Text('Supplier Orders',
                style: AppTextStyles.h3.copyWith(fontSize: 18)),
            const SizedBox(height: 16),
            ...supplierOrders.map((so) => _SupplierOrderCard(supplierOrder: so)),
          ],

          if (order.notes != null && order.notes!.isNotEmpty) ...[
            const SizedBox(height: 24),
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
                    Text('Notes',
                        style: AppTextStyles.body
                            .copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(order.notes!, style: AppTextStyles.body),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(OrderStatus status) {
    String label;
    Color color;
    switch (status) {
      case OrderStatus.draft:
        label = 'Draft';
        color = AppColors.textSecondary;
      case OrderStatus.confirmed:
        label = 'Confirmed';
        color = AppColors.primary;
      case OrderStatus.sent:
        label = 'Sent to Suppliers';
        color = Colors.blue;
      case OrderStatus.partiallyFulfilled:
        label = 'Partially Fulfilled';
        color = AppColors.warning;
      case OrderStatus.completed:
        label = 'Completed';
        color = AppColors.success;
      case OrderStatus.cancelled:
        label = 'Cancelled';
        color = AppColors.error;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class _SupplierOrderCard extends StatelessWidget {
  final SupplierOrder supplierOrder;
  const _SupplierOrderCard({required this.supplierOrder});

  @override
  Widget build(BuildContext context) {
    final so = supplierOrder;
    final hasResponse = so.response != null;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    so.supplierName,
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(so.supplierEmail, style: AppTextStyles.label),
                const SizedBox(width: 12),
                StatusChip(so.status == 'pending'
                    ? 'Pending'
                    : so.status == 'acknowledged'
                        ? 'Acknowledged'
                        : so.status),
              ],
            ),
            const Divider(height: 16),
            // Items summary
            ...so.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text('${item.productName} (${item.sku})')),
                      Text('${item.quantity} units'),
                      const SizedBox(width: 16),
                      Text('\$${item.estimatedCost.toStringAsFixed(2)}'),
                    ],
                  ),
                )),
            const Divider(height: 16),
            Row(
              children: [
                Text(
                  'Total: \$${so.totalEstimatedCost.toStringAsFixed(2)}',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                if (hasResponse) ...[
                  const Icon(Icons.check_circle,
                      color: AppColors.success, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Responded: ${so.response!.estimatedDeliveryDays ?? "?"} days, '
                    '\$${so.response!.totalCost?.toStringAsFixed(2) ?? "?"}',
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                ] else
                  Text('Awaiting supplier response',
                      style: AppTextStyles.label),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
