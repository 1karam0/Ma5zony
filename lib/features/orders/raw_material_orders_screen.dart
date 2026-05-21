import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/raw_material_purchase_order.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class RawMaterialOrdersScreen extends StatefulWidget {
  const RawMaterialOrdersScreen({super.key});

  @override
  State<RawMaterialOrdersScreen> createState() =>
      _RawMaterialOrdersScreenState();
}

class _RawMaterialOrdersScreenState extends State<RawMaterialOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final orders = state.rmPurchaseOrders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Row(
            children: [
              const SectionHeader(title: 'Raw Material Orders'),
              const Spacer(),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          tabs: const [
            Tab(text: 'Draft'),
            Tab(text: 'Sent'),
            Tab(text: 'Received'),
            Tab(text: 'Cancelled'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _OrderList(
                  orders: orders.where((o) => o.status == 'draft').toList()),
              _OrderList(
                  orders: orders.where((o) => o.status == 'sent').toList()),
              _OrderList(
                  orders: orders.where((o) => o.status == 'received').toList()),
              _OrderList(
                  orders:
                      orders.where((o) => o.status == 'cancelled').toList()),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderList extends StatelessWidget {
  final List<RawMaterialPurchaseOrder> orders;

  const _OrderList({required this.orders});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(
        child: EmptyStateWidget(
          icon: Icons.inventory_2_outlined,
          title: 'No orders in this status',
          description: 'Raw material orders will appear here once created.',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _OrderCard(order: orders[i]),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final RawMaterialPurchaseOrder order;

  const _OrderCard({required this.order});

  Color get _statusColor {
    return switch (order.status) {
      'sent' => AppColors.info,
      'received' => AppColors.success,
      'cancelled' => AppColors.error,
      _ => AppColors.warning,
    };
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final date = DateFormat('dd MMM yyyy').format(order.createdAt);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(order.supplierName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(order.status.toUpperCase(),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(date,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            ...order.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                            '${item.rawMaterialName} — ${item.quantityOrdered} ${item.unitOfMeasure}',
                            style:
                                TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                      ),
                      Text('EGP ${fmt.format(item.totalCost)}',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                )),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Total: EGP ${fmt.format(order.totalCost)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary)),
                if (order.status == 'draft') ...[
                  const SizedBox(width: 12),
                  FilledButton.tonal(
                    onPressed: () async {
                      await context
                          .read<AppState>()
                          .confirmRawMaterialPurchaseOrder(order.id);
                    },
                    child: const Text('Mark Sent'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
