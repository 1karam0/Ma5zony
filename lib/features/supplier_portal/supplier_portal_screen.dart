import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ma5zony — Supplier Portal'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 64, color: AppColors.error),
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: AppTextStyles.body
                              .copyWith(color: AppColors.error)),
                    ],
                  ),
                )
              : _buildOrderView(),
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
              Card(
                color: AppColors.primary.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(Icons.local_shipping,
                          size: 40, color: AppColors.primary),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hello, ${order.supplierName}!',
                              style: AppTextStyles.h3,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'You have a new purchase order to review. '
                              'Please check the items below and submit your delivery estimate and cost.',
                              style: AppTextStyles.body,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Order info
              Text(
                'Order placed on ${DateFormat.yMMMd().format(order.createdAt)}',
                style: AppTextStyles.label,
              ),
              const SizedBox(height: 16),

              // Items table
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
                      Text('Ordered Items',
                          style: AppTextStyles.body
                              .copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Product')),
                            DataColumn(label: Text('SKU')),
                            DataColumn(label: Text('Quantity')),
                            DataColumn(label: Text('Unit Cost')),
                            DataColumn(label: Text('Line Total')),
                          ],
                          rows: order.items.map((item) {
                            return DataRow(cells: [
                              DataCell(Text(item.productName)),
                              DataCell(Text(item.sku)),
                              DataCell(Text('${item.quantity}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text(
                                  '\$${item.unitCost.toStringAsFixed(2)}')),
                              DataCell(Text(
                                '\$${item.estimatedCost.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              )),
                            ]);
                          }).toList(),
                        ),
                      ),
                      const Divider(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Total: \$${order.totalEstimatedCost.toStringAsFixed(2)}',
                          style: AppTextStyles.h3.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Response form
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
                      Row(
                        children: [
                          Icon(
                            hasResponded
                                ? Icons.check_circle
                                : Icons.pending_actions,
                            color: hasResponded
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            hasResponded
                                ? 'Your Response (Submitted)'
                                : 'Your Response',
                            style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
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
                                border: OutlineInputBorder(),
                                helperText: 'How many days to fulfill this order?',
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
                                border: OutlineInputBorder(),
                                helperText: 'Your final quoted cost for this order',
                                prefixText: '\$ ',
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
                          border: OutlineInputBorder(),
                          helperText:
                              'Any additional information, constraints, or comments',
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
                              : Icon(hasResponded ? Icons.update : Icons.send),
                          label: Text(_submitting
                              ? 'Submitting...'
                              : hasResponded
                                  ? 'Update Response'
                                  : 'Submit Response'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
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
