import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/raw_material_purchase_order.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class CreateRawMaterialOrderScreen extends StatefulWidget {
  final String productId;
  final double forecastQty;

  const CreateRawMaterialOrderScreen({
    super.key,
    required this.productId,
    required this.forecastQty,
  });

  @override
  State<CreateRawMaterialOrderScreen> createState() =>
      _CreateRawMaterialOrderScreenState();
}

class _CreateRawMaterialOrderScreenState
    extends State<CreateRawMaterialOrderScreen> {
  List<RawMaterialPurchaseOrder>? _orders;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _buildOrders();
  }

  Future<void> _buildOrders() async {
    try {
      final orders = await context.read<AppState>().createRawMaterialOrders(
            widget.productId,
            widget.forecastQty,
          );
      setState(() {
        _orders = orders;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveDraft() async {
    if (_orders == null) return;
    setState(() => _saving = true);
    try {
      await context.read<AppState>().saveRawMaterialPurchaseOrders(_orders!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Orders saved as draft.'),
          backgroundColor: AppColors.success,
        ));
        context.go('/orders/raw-materials');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmAndSend() async {
    if (_orders == null) return;
    setState(() => _saving = true);
    final appState = context.read<AppState>();
    try {
      await appState.saveRawMaterialPurchaseOrders(_orders!);
      // Mark each order 'sent' then attempt to notify its supplier.
      final sentTo = <String>[];
      final failedFor = <String>[];
      for (final o in _orders!) {
        await appState.confirmRawMaterialPurchaseOrder(o.id);
        final supplier = appState.suppliers
            .where((s) => s.id == o.supplierId)
            .firstOrNull;
        final supplierName = supplier?.name ?? 'Supplier';
        final ok = await appState.sendRawMaterialOrderEmail(o.id);
        if (ok) {
          sentTo.add(supplierName);
        } else {
          failedFor.add(supplierName);
        }
      }
      if (mounted) {
        final parts = <String>[];
        if (sentTo.isNotEmpty) {
          parts.add('Emailed: ${sentTo.join(", ")}');
        }
        if (failedFor.isNotEmpty) {
          parts.add('Email failed (order still sent): ${failedFor.join(", ")}');
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(parts.isEmpty
              ? 'Orders sent to suppliers.'
              : parts.join(' • ')),
          backgroundColor:
              failedFor.isEmpty ? AppColors.success : AppColors.warning,
          duration: const Duration(seconds: 5),
        ));
        context.go('/orders/raw-materials');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final product =
        state.products.where((p) => p.id == widget.productId).firstOrNull;
    final fmt = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Create Raw Material Orders'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 1,
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: AppColors.error)))
              : _orders == null || _orders!.isEmpty
                  ? Center(
                      child: EmptyStateWidget(
                        icon: Icons.inventory_2_outlined,
                        title: 'No BOM configured',
                        description:
                            'Set up a Bill of Materials for this product to create raw material orders.',
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Context banner
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.infoBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.info_outline,
                                          color: AppColors.info),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'For: ${product?.name ?? widget.productId}  '
                                          '|  Qty to produce: ${widget.forecastQty.toStringAsFixed(0)} units',
                                          style: const TextStyle(
                                              color: AppColors.info,
                                              fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Orders per supplier
                                ..._orders!.map(
                                  (order) => _SupplierOrderCard(
                                    order: order,
                                    fmt: fmt,
                                  ),
                                ),

                                // Grand total
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border:
                                        Border.all(color: AppColors.border),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      const Text('Total across all suppliers: ',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15)),
                                      Text(
                                        'EGP ${fmt.format(_orders!.fold<double>(0, (s, o) => s + o.totalCost))}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 17,
                                            color: AppColors.primary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Action bar
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: _saving ? null : _saveDraft,
                                child: const Text('Save as Draft'),
                              ),
                              const SizedBox(width: 12),
                              FilledButton(
                                onPressed: _saving ? null : _confirmAndSend,
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary),
                                child: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Text('Confirm & Send to Suppliers'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class _SupplierOrderCard extends StatefulWidget {
  final RawMaterialPurchaseOrder order;
  final NumberFormat fmt;

  const _SupplierOrderCard({required this.order, required this.fmt});

  @override
  State<_SupplierOrderCard> createState() => _SupplierOrderCardState();
}

class _SupplierOrderCardState extends State<_SupplierOrderCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping_outlined,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Supplier: ${widget.order.supplierName}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          if (_expanded) ...[
            const Divider(height: 1),
            // Table header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text('Item',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: AppColors.textSecondary))),
                  SizedBox(
                      width: 90,
                      child: Text('Total Qty',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: AppColors.textSecondary))),
                  SizedBox(
                      width: 80,
                      child: Text('Unit Cost',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: AppColors.textSecondary))),
                  SizedBox(
                      width: 90,
                      child: Text('Total',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: AppColors.textSecondary))),
                ],
              ),
            ),
            const Divider(height: 1),
            ...widget.order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(item.rawMaterialName,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary)),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                          '${item.quantityOrdered.toStringAsFixed(1)} ${item.unitOfMeasure}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary)),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(
                          'EGP ${widget.fmt.format(item.unitCost)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                          'EGP ${widget.fmt.format(item.totalCost)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Subtotal: EGP ${widget.fmt.format(widget.order.totalCost)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
