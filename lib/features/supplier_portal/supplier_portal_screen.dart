import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:ma5zony/models/supplier_order.dart';
import 'package:ma5zony/utils/constants.dart';

/// A standalone supplier portal screen accessible via a unique access token.
/// No Firebase authentication required — the token grants access to a
/// specific supplier order.
class SupplierPortalScreen extends StatefulWidget {
  final String accessToken;
  const SupplierPortalScreen({super.key, required this.accessToken});

  @override
  State<SupplierPortalScreen> createState() => _SupplierPortalScreenState();
}

class _SupplierPortalScreenState extends State<SupplierPortalScreen> {
  SupplierOrder? _order;
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  final _deliveryDaysCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  @override
  void dispose() {
    _deliveryDaysCtrl.dispose();
    _costCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('supplierOrders')
          .where('accessToken', isEqualTo: widget.accessToken)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        setState(() {
          _error = 'Order not found or invalid access link.';
          _loading = false;
        });
        return;
      }

      final doc = snap.docs.first;
      final order = SupplierOrder.fromFirestore(doc.id, doc.data());

      // Check token expiration
      if (order.expiresAt != null && order.expiresAt!.isBefore(DateTime.now())) {
        setState(() {
          _error = 'This access link has expired. Please contact the buyer for a new link.';
          _loading = false;
        });
        return;
      }

      // Pre-fill response fields if already responded
      if (order.response != null) {
        _deliveryDaysCtrl.text =
            '${order.response!.estimatedDeliveryDays ?? ''}';
        _costCtrl.text = order.response!.totalCost?.toStringAsFixed(2) ?? '';
        _notesCtrl.text = order.response!.notes ?? '';
      }

      setState(() {
        _order = order;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load order: $e';
        _loading = false;
      });
    }
  }

  Future<void> _submitResponse() async {
    if (_order == null) return;
    final deliveryDays = int.tryParse(_deliveryDaysCtrl.text);
    final cost = double.tryParse(_costCtrl.text);

    if (deliveryDays == null || deliveryDays <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid delivery time.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await FirebaseFirestore.instance
          .collection('supplierOrders')
          .doc(_order!.id)
          .update({
        'status': 'acknowledged',
        'response': {
          'estimatedDeliveryDays': deliveryDays,
          'totalCost': cost,
          'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          'respondedAt': FieldValue.serverTimestamp(),
        },
      });

      setState(() {
        _order!.status = 'acknowledged';
        _order!.response = SupplierResponse(
          estimatedDeliveryDays: deliveryDays,
          totalCost: cost,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          respondedAt: DateTime.now(),
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Response submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          // Portal top banner
          Container(
            color: AppColors.sidebarBg,
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: AppRadius.sharp,
                  ),
                  child: const Icon(Icons.inventory_2,
                      color: AppColors.primary, size: 14),
                ),
                const SizedBox(width: 10),
                Text(
                  'Ma5zony',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.sidebarTextActive,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.sidebarBgHover,
                    borderRadius: AppRadius.pill,
                    border: Border.all(color: AppColors.sidebarAccent),
                  ),
                  child: Text(
                    'Supplier Portal',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.sidebarText),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.lock_outline,
                    size: 14, color: AppColors.sidebarText),
                const SizedBox(width: 4),
                Text('Secure link',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.sidebarText)),
              ],
            ),
          ),
          // Body
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorState()
                    : _buildOrderView(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: AppRadius.soft,
            ),
            child: const Icon(Icons.error_outline,
                size: 28, color: AppColors.error),
          ),
          const SizedBox(height: 16),
          Text('Access Error', style: AppTextStyles.h2),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.body
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderView() {
    final order = _order!;
    final hasResponded = order.response != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.soft,
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: AppRadius.soft,
                      ),
                      child: const Icon(Icons.local_shipping,
                          size: 22, color: AppColors.primary),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hello, ${order.supplierName}',
                              style: AppTextStyles.h2),
                          const SizedBox(height: 4),
                          Text(
                            'You have a purchase order to review. '
                            'Check the items and submit your delivery estimate.',
                            style: AppTextStyles.body.copyWith(
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              Text(
                'Order placed ${DateFormat.yMMMd().format(order.createdAt)}',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSubdued),
              ),

              const SizedBox(height: 20),

              // Items table
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.soft,
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: Text('Ordered Items', style: AppTextStyles.h3),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('PRODUCT')),
                          DataColumn(label: Text('SKU')),
                          DataColumn(label: Text('QTY')),
                          DataColumn(label: Text('UNIT COST')),
                          DataColumn(label: Text('LINE TOTAL')),
                        ],
                        rows: order.items.map((item) {
                          return DataRow(cells: [
                            DataCell(Text(item.productName)),
                            DataCell(Text(item.sku,
                                style: AppTextStyles.mono)),
                            DataCell(Text('${item.quantity}')),
                            DataCell(Text(
                                'EGP ${item.unitCost.toStringAsFixed(2)}')),
                            DataCell(Text(
                              'EGP ${item.estimatedCost.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            )),
                          ]);
                        }).toList(),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('Total  ', style: AppTextStyles.label),
                          Text(
                            'EGP ${order.totalEstimatedCost.toStringAsFixed(2)}',
                            style: AppTextStyles.h3
                                .copyWith(color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Response form
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.soft,
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          hasResponded
                              ? Icons.check_circle_outline
                              : Icons.pending_actions_outlined,
                          color: hasResponded
                              ? AppColors.success
                              : AppColors.warning,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          hasResponded
                              ? 'Your Response (Submitted)'
                              : 'Your Response',
                          style: AppTextStyles.h3,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _deliveryDaysCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Estimated Delivery Time (days) *',
                              helperText:
                                  'How many days to fulfill this order?',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _costCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Total Cost (\$)',
                              helperText: 'Your final quoted cost',
                              prefixText: 'EGP ',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        helperText:
                            'Any additional information or constraints',
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submitResponse,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(hasResponded
                                ? Icons.update
                                : Icons.send_outlined),
                        label: Text(_submitting
                            ? 'Submitting…'
                            : hasResponded
                                ? 'Update Response'
                                : 'Submit Response'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
