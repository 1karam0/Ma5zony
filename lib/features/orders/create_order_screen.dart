// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/purchase_order.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  late PurchaseOrder _draftOrder;
  final _notesCtrl = TextEditingController();
  bool _saving = false;
  final Map<String, TextEditingController> _qtyControllers = {};

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _draftOrder = appState.buildOrderFromRecommendations();
    // Initialize qty controllers
    for (final item in _draftOrder.items) {
      _qtyControllers[item.productId] =
          TextEditingController(text: '${item.quantity}');
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _removeItem(int index) {
    setState(() {
      final item = _draftOrder.items[index];
      _qtyControllers.remove(item.productId);
      _draftOrder.items.removeAt(index);
    });
  }

  Future<void> _confirmOrder() async {
    if (_draftOrder.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item to the order.')),
      );
      return;
    }

    // Update quantities from controllers
    for (final item in _draftOrder.items) {
      final ctrl = _qtyControllers[item.productId];
      if (ctrl != null) {
        item.quantity = int.tryParse(ctrl.text) ?? item.quantity;
      }
    }

    // Remove items with zero quantity
    _draftOrder.items.removeWhere((i) => i.quantity <= 0);
    if (_draftOrder.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All items have zero quantity.')),
      );
      return;
    }

    _draftOrder.notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final appState = context.read<AppState>();
      final savedOrder = await appState.confirmPurchaseOrder(_draftOrder);
      if (savedOrder != null && mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Order confirmed! Supplier orders created.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/orders');
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to create order: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Group items by supplier
    final bySupplier = <String?, List<MapEntry<int, PurchaseOrderItem>>>{};
    for (var i = 0; i < _draftOrder.items.length; i++) {
      final item = _draftOrder.items[i];
      bySupplier
          .putIfAbsent(item.supplierName ?? 'Unassigned', () => [])
          .add(MapEntry(i, item));
    }

    final noSupplierItems =
        _draftOrder.items.where((i) => i.supplierId == null).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                onPressed: () => context.go('/replenishment'),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Text('Review Purchase Order', style: AppTextStyles.h3),
              const Spacer(),
              Text(
                'Total: \$${_draftOrder.totalEstimatedCost.toStringAsFixed(2)}',
                style: AppTextStyles.h3.copyWith(color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_draftOrder.totalItems} items · ${_draftOrder.totalQuantity} units',
            style: AppTextStyles.label,
          ),

          if (noSupplierItems.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${noSupplierItems.length} item(s) have no supplier assigned. '
                        'Please assign suppliers in the Products page before sending emails.',
                        style: AppTextStyles.body,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Items grouped by supplier
          ...bySupplier.entries.map((entry) {
            final supplierName = entry.key ?? 'Unassigned';
            final items = entry.value;
            final supplierTotal = items.fold<double>(
                0, (sum, e) => sum + e.value.estimatedCost);

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.local_shipping,
                          color: supplierName == 'Unassigned'
                              ? Colors.orange
                              : AppColors.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                supplierName,
                                style: AppTextStyles.body.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              if (items.first.value.supplierEmail != null)
                                Text(
                                  items.first.value.supplierEmail!,
                                  style: AppTextStyles.label,
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '\$${supplierTotal.toStringAsFixed(2)}',
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    ...items.map((entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: AppTextStyles.body.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(item.sku, style: AppTextStyles.label),
                                ],
                              ),
                            ),
                            // Unit cost
                            Expanded(
                              child: Text(
                                '\$${item.unitCost.toStringAsFixed(2)}/unit',
                                style: AppTextStyles.label,
                              ),
                            ),
                            // Quantity input
                            SizedBox(
                              width: 80,
                              child: TextFormField(
                                controller: _qtyControllers[item.productId],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Qty',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Line total
                            SizedBox(
                              width: 80,
                              child: Text(
                                '\$${((int.tryParse(_qtyControllers[item.productId]?.text ?? '') ?? item.quantity) * item.unitCost).toStringAsFixed(2)}',
                                style: AppTextStyles.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              color: AppColors.error,
                              onPressed: () => _removeItem(idx),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }),

          // Notes
          const SizedBox(height: 8),
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
                  Text(
                    'Order Notes (optional)',
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText:
                          'Add any notes for this order (internal use only)...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Actions
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => context.go('/replenishment'),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _saving ? null : _confirmOrder,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(_saving ? 'Creating...' : 'Confirm Order'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
