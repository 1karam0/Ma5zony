import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ma5zony/utils/constants.dart';

/// Factory portal screen — accessible via access token (no auth).
/// Factories can view raw material orders assigned to them and update status.
class FactoryPortalScreen extends StatefulWidget {
  final String accessToken;
  const FactoryPortalScreen({super.key, required this.accessToken});

  @override
  State<FactoryPortalScreen> createState() => _FactoryPortalScreenState();
}

class _FactoryPortalScreenState extends State<FactoryPortalScreen> {
  Map<String, dynamic>? _order;
  String? _docId;
  bool _loading = true;
  String? _error;
  bool _submitting = false;
  final _notesCtrl = TextEditingController();
  final _deliveryDaysCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _deliveryDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('factoryOrders')
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
      final data = doc.data();

      // Check token expiration
      if (data['expiresAt'] != null) {
        final expiresAt = (data['expiresAt'] as Timestamp).toDate();
        if (expiresAt.isBefore(DateTime.now())) {
          setState(() {
            _error = 'This access link has expired. Please contact the buyer for a new link.';
            _loading = false;
          });
          return;
        }
      }

      setState(() {
        _docId = doc.id;
        _order = data;
        _notesCtrl.text = (_order!['factoryNotes'] as String?) ?? '';
        _deliveryDaysCtrl.text =
            '${(_order!['estimatedDeliveryDays'] as int?) ?? ''}';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load order: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Factory Portal'),
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
                          size: 48, color: AppColors.error),
                      const SizedBox(height: 12),
                      Text(_error!, style: AppTextStyles.body),
                    ],
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final order = _order!;
    final status = order['status'] as String? ?? 'unknown';
    final materialName =
        order['materialName'] as String? ?? 'Unknown Material';
    final quantity = order['quantity'] as int? ?? 0;
    final unit = order['unit'] as String? ?? 'pcs';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Raw Material Order',
                          style: AppTextStyles.h2),
                      const SizedBox(height: 16),
                      _DetailRow(
                          label: 'Material', value: materialName),
                      _DetailRow(
                          label: 'Quantity',
                          value: '$quantity $unit'),
                      _DetailRow(
                          label: 'Status',
                          value: _statusLabel(status)),
                      if (order['requestedDate'] != null)
                        _DetailRow(
                            label: 'Requested',
                            value: _formatTimestamp(
                                order['requestedDate'])),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _deliveryDaysCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Estimated Delivery Days',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Notes / Comments',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Action buttons based on status
              if (status == 'pending')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Accept Order'),
                    onPressed:
                        _submitting ? null : () => _updateStatus('accepted'),
                  ),
                ),
              if (status == 'accepted')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Processing'),
                    onPressed: _submitting
                        ? null
                        : () => _updateStatus('in_progress'),
                  ),
                ),
              if (status == 'in_progress')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Mark Completed'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
                    onPressed: _submitting
                        ? null
                        : () => _updateStatus('completed'),
                  ),
                ),
              if (status == 'completed')
                Card(
                  color: AppColors.success.withValues(alpha: 0.1),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: AppColors.success),
                        SizedBox(width: 12),
                        Text('This order has been completed.'),
                      ],
                    ),
                  ),
                ),
              if (_submitting)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_docId == null) return;
    setState(() => _submitting = true);
    try {
      final data = <String, dynamic>{
        'status': newStatus,
        'factoryNotes': _notesCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final days = int.tryParse(_deliveryDaysCtrl.text.trim());
      if (days != null) {
        data['estimatedDeliveryDays'] = days;
      }
      if (newStatus == 'completed') {
        data['completedDate'] = FieldValue.serverTimestamp();
      }
      await FirebaseFirestore.instance
          .collection('factoryOrders')
          .doc(_docId!)
          .update(data);
      setState(() {
        _order!['status'] = newStatus;
        _submitting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Status updated to ${_statusLabel(newStatus)}')),
        );
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  String _statusLabel(String s) => switch (s) {
        'pending' => 'Pending',
        'accepted' => 'Accepted',
        'in_progress' => 'In Progress',
        'completed' => 'Completed',
        _ => s,
      };

  String _formatTimestamp(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    return ts.toString();
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: AppTextStyles.label),
          ),
          Expanded(child: Text(value, style: AppTextStyles.body)),
        ],
      ),
    );
  }
}
