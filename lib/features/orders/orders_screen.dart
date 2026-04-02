// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/purchase_order.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final orders = state.purchaseOrders;

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Purchase Orders',
            actions: [
              ElevatedButton.icon(
                onPressed: () => context.go('/orders/create'),
                icon: const Icon(Icons.add),
                label: const Text('New Order'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),

          // KPIs
          Row(
            children: [
              Expanded(
                child: KPICard(
                  title: 'Total Orders',
                  value: '${orders.length}',
                  icon: Icons.receipt_long,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Pending',
                  value:
                      '${orders.where((o) => o.status == OrderStatus.confirmed || o.status == OrderStatus.sent).length}',
                  icon: Icons.pending_actions,
                  color: AppColors.warning,
                  isAlert: orders.any((o) =>
                      o.status == OrderStatus.confirmed ||
                      o.status == OrderStatus.sent),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Completed',
                  value:
                      '${orders.where((o) => o.status == OrderStatus.completed).length}',
                  icon: Icons.check_circle,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (orders.isEmpty)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.receipt_long,
                          size: 48, color: AppColors.textSecondary),
                      const SizedBox(height: 12),
                      Text(
                        'No purchase orders yet.',
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Go to Replenishment to create an order from low-stock suggestions.',
                        style: AppTextStyles.label,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Order ID')),
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Items')),
                      DataColumn(label: Text('Total Cost')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Action')),
                    ],
                    rows: orders.map((order) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              '#${order.id.substring(0, order.id.length > 8 ? 8 : order.id.length).toUpperCase()}',
                              style: AppTextStyles.body
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DataCell(Text(
                            DateFormat.yMMMd().format(order.createdAt),
                          )),
                          DataCell(Text(
                            '${order.totalItems} items (${order.totalQuantity} units)',
                          )),
                          DataCell(Text(
                            '\$${order.totalEstimatedCost.toStringAsFixed(2)}',
                            style: AppTextStyles.body
                                .copyWith(fontWeight: FontWeight.w600),
                          )),
                          DataCell(_OrderStatusChip(order.status)),
                          DataCell(
                            TextButton(
                              onPressed: () =>
                                  context.go('/orders/${order.id}'),
                              child: const Text('View'),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderStatusChip extends StatelessWidget {
  final OrderStatus status;
  const _OrderStatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    switch (status) {
      case OrderStatus.draft:
        label = 'Draft';
        color = AppColors.textSecondary;
        break;
      case OrderStatus.confirmed:
        label = 'Confirmed';
        color = AppColors.primary;
        break;
      case OrderStatus.sent:
        label = 'Sent to Suppliers';
        color = Colors.blue;
        break;
      case OrderStatus.partiallyFulfilled:
        label = 'Partially Fulfilled';
        color = AppColors.warning;
        break;
      case OrderStatus.completed:
        label = 'Completed';
        color = AppColors.success;
        break;
      case OrderStatus.cancelled:
        label = 'Cancelled';
        color = AppColors.error;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: AppTextStyles.label.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
