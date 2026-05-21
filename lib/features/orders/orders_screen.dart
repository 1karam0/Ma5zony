import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/purchase_order.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = [
    ('All', null),
    ('Draft', OrderStatus.draft),
    ('Confirmed', OrderStatus.confirmed),
    ('Sent', OrderStatus.sent),
    ('Completed', OrderStatus.completed),
    ('Cancelled', OrderStatus.cancelled),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final allOrders = state.purchaseOrders;
    final supplierMap = {for (final s in state.suppliers) s.id: s.name};

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
                  value: '${allOrders.length}',
                  icon: Icons.receipt_long,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Pending',
                  value:
                      '${allOrders.where((o) => o.status == OrderStatus.confirmed || o.status == OrderStatus.sent).length}',
                  icon: Icons.pending_actions,
                  color: AppColors.warning,
                  isAlert: allOrders.any((o) =>
                      o.status == OrderStatus.confirmed ||
                      o.status == OrderStatus.sent),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Completed',
                  value:
                      '${allOrders.where((o) => o.status == OrderStatus.completed).length}',
                  icon: Icons.check_circle,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Status tab bar
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.border),
            ),
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  indicatorSize: TabBarIndicatorSize.tab,
                  onTap: (_) => setState(() {}),
                  tabs: _tabs.map((t) {
                    final count = t.$2 == null
                        ? allOrders.length
                        : allOrders.where((o) => o.status == t.$2).length;
                    return Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.$1),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600),
                            ),
                          )
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const Divider(height: 1),
                Builder(builder: (context) {
                  final selectedStatus = _tabs[_tabController.index].$2;
                  final orders = selectedStatus == null
                      ? allOrders
                      : allOrders
                          .where((o) => o.status == selectedStatus)
                          .toList();

                  if (orders.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: EmptyStateWidget(
                        icon: Icons.receipt_long_outlined,
                        title: 'No purchase orders yet',
                        description:
                            'Go to Replenishment to create orders from\nlow-stock suggestions.',
                        primaryLabel: 'Go to Replenishment',
                        onPrimary: () => context.go('/replenishment'),
                        secondaryLabel: 'Create Manually',
                        onSecondary: () => context.go('/orders/create'),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          AppColors.primary.withValues(alpha: 0.04),
                        ),
                        columns: const [
                          DataColumn(label: Text('PO Number')),
                          DataColumn(label: Text('Supplier')),
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Items')),
                          DataColumn(label: Text('Total Cost')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Action')),
                        ],
                        rows: orders.map((order) {
                          // Human-readable PO number: first 8 chars of doc ID
                          final poNum =
                              'PO-${order.id.substring(0, order.id.length > 6 ? 6 : order.id.length).toUpperCase()}';
                          // Resolve supplier name from first line item
                          final firstSupplierId = order.items.isNotEmpty
                              ? order.items.first.supplierId
                              : null;
                          final supplierName =
                              supplierMap[firstSupplierId ?? ''] ?? '—';
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  poNum,
                                  style: AppTextStyles.body.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              DataCell(Text(supplierName)),
                              DataCell(Text(
                                DateFormat.yMMMd().format(order.createdAt),
                              )),
                              DataCell(Text(
                                '${order.totalItems} items',
                              )),
                              DataCell(Text(
                                'EGP ${order.totalEstimatedCost.toStringAsFixed(2)}',
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
                  );
                }),
              ],
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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
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
