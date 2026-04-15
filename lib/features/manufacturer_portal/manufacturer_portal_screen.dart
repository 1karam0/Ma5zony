import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ma5zony/utils/constants.dart';

/// Manufacturer portal screen — accessible via access token (no auth).
/// Manufacturers can view their assigned production orders and update status.
class ManufacturerPortalScreen extends StatefulWidget {
  final String accessToken;
  const ManufacturerPortalScreen({super.key, required this.accessToken});

  @override
  State<ManufacturerPortalScreen> createState() =>
      _ManufacturerPortalScreenState();
}

class _ManufacturerPortalScreenState extends State<ManufacturerPortalScreen> {
  Map<String, dynamic>? _order;
  String? _docId;
  bool _loading = true;
  String? _error;
  bool _submitting = false;
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('manufacturerOrders')
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
        _notesCtrl.text = (_order!['manufacturerNotes'] as String?) ?? '';
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
        title: const Text('Manufacturer Portal'),
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
    final productName = order['productName'] as String? ?? 'Unknown Product';
    final quantity = order['quantity'] as int? ?? 0;
    final estimatedCost = (order['estimatedCost'] as num?)?.toDouble() ?? 0;

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
                      Text('Production Order', style: AppTextStyles.h2),
                      const SizedBox(height: 16),
                      _DetailRow(label: 'Product', value: productName),
                      _DetailRow(
                          label: 'Quantity', value: '$quantity units'),
                      _DetailRow(
                          label: 'Estimated Cost',
                          value:
                              '\$${estimatedCost.toStringAsFixed(2)}'),
                      _DetailRow(
                          label: 'Status',
                          value: _statusLabel(status)),
                      const SizedBox(height: 16),
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

              // Material orders linked
              if (order['rawMaterialOrders'] is List) ...[
                Text('Required Materials', style: AppTextStyles.h3),
                const SizedBox(height: 8),
                Card(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Material')),
                      DataColumn(label: Text('Quantity')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows:
                        (order['rawMaterialOrders'] as List)
                            .map((rm) {
                      final map = rm as Map<String, dynamic>;
                      return DataRow(cells: [
                        DataCell(
                            Text(map['materialName'] as String? ?? '—')),
                        DataCell(Text('${map['quantity'] ?? 0}')),
                        DataCell(Text(
                            _statusLabel(map['status'] as String? ?? ''))),
                      ]);
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Action buttons
              if (status == 'materials_ready')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Production'),
                    onPressed: _submitting
                        ? null
                        : () => _updateStatus('in_production'),
                  ),
                ),
              if (status == 'in_production')
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
        'manufacturerNotes': _notesCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (newStatus == 'completed') {
        data['completedAt'] = FieldValue.serverTimestamp();
      }
      await FirebaseFirestore.instance
          .collection('manufacturerOrders')
          .doc(_docId!)
          .update(data);
      setState(() {
        _order!['status'] = newStatus;
        _submitting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to ${_statusLabel(newStatus)}')),
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
        'draft' => 'Draft',
        'approved' => 'Approved',
        'materials_ordered' => 'Materials Ordered',
        'materials_ready' => 'Materials Ready',
        'in_production' => 'In Production',
        'completed' => 'Completed',
        _ => s,
      };
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
