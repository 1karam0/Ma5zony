import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/raw_material.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class RawMaterialsScreen extends StatefulWidget {
  const RawMaterialsScreen({super.key});

  @override
  State<RawMaterialsScreen> createState() => _RawMaterialsScreenState();
}

class _RawMaterialsScreenState extends State<RawMaterialsScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final suppliers = {for (final s in state.suppliers) s.id: s.name};

    final materials = state.rawMaterials.where((m) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return m.name.toLowerCase().contains(q) ||
          m.sku.toLowerCase().contains(q);
    }).toList();

    // KPIs
    final totalMaterials = state.rawMaterials.length;
    final lowStock =
        state.rawMaterials.where((m) => m.currentStock <= m.safetyStock).length;
    final totalValue = state.rawMaterials.fold<double>(
        0, (sum, m) => sum + m.currentStock * m.unitCost);

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Raw Materials',
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Material'),
                onPressed: () => _showFormDialog(context, state),
              ),
            ],
          ),
          // KPI row
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 200,
                child: KPICard(
                  title: 'Total Materials',
                  value: '$totalMaterials',
                  icon: Icons.category,
                ),
              ),
              SizedBox(
                width: 200,
                child: KPICard(
                  title: 'Low Stock',
                  value: '$lowStock',
                  icon: Icons.warning_amber,
                  color: lowStock > 0 ? AppColors.error : AppColors.success,
                  isAlert: lowStock > 0,
                ),
              ),
              SizedBox(
                width: 200,
                child: KPICard(
                  title: 'Inventory Value',
                  value: '\$${totalValue.toStringAsFixed(0)}',
                  icon: Icons.attach_money,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Search bar
          SizedBox(
            width: 300,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search materials...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(height: 16),
          // Data table
          Card(
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('SKU')),
                  DataColumn(label: Text('Unit')),
                  DataColumn(label: Text('Unit Cost')),
                  DataColumn(label: Text('Stock')),
                  DataColumn(label: Text('Safety Stock')),
                  DataColumn(label: Text('Supplier')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: materials.map((m) {
                  final isLow = m.currentStock <= m.safetyStock;
                  return DataRow(cells: [
                    DataCell(Text(m.name)),
                    DataCell(Text(m.sku)),
                    DataCell(Text(m.unit)),
                    DataCell(Text('\$${m.unitCost.toStringAsFixed(2)}')),
                    DataCell(Text(
                      '${m.currentStock}',
                      style: TextStyle(
                        color: isLow ? AppColors.error : null,
                        fontWeight: isLow ? FontWeight.bold : null,
                      ),
                    )),
                    DataCell(Text('${m.safetyStock}')),
                    DataCell(Text(suppliers[m.supplierId] ?? '—')),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          tooltip: 'Edit',
                          onPressed: () =>
                              _showFormDialog(context, state, existing: m),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18),
                          tooltip: 'Delete',
                          color: AppColors.error,
                          onPressed: () => _confirmDelete(context, state, m),
                        ),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
          if (materials.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.category_outlined,
                        size: 48, color: AppColors.textSecondary),
                    SizedBox(height: 8),
                    Text('No raw materials yet',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showFormDialog(BuildContext context, AppState state,
      {RawMaterial? existing}) {
    showDialog(
      context: context,
      builder: (_) => _RawMaterialFormDialog(
        state: state,
        existing: existing,
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, AppState state, RawMaterial m) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete Material'),
        content: Text('Delete "${m.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await state.deleteRawMaterial(m.id);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Material deleted')),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _RawMaterialFormDialog extends StatefulWidget {
  final AppState state;
  final RawMaterial? existing;

  const _RawMaterialFormDialog({required this.state, this.existing});

  @override
  State<_RawMaterialFormDialog> createState() => _RawMaterialFormDialogState();
}

class _RawMaterialFormDialogState extends State<_RawMaterialFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _unitCostCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _safetyCtrl;
  String? _supplierId;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _skuCtrl = TextEditingController(text: e?.sku ?? '');
    _unitCtrl = TextEditingController(text: e?.unit ?? 'pcs');
    _unitCostCtrl =
        TextEditingController(text: e != null ? '${e.unitCost}' : '');
    _stockCtrl =
        TextEditingController(text: e != null ? '${e.currentStock}' : '0');
    _safetyCtrl =
        TextEditingController(text: e != null ? '${e.safetyStock}' : '0');
    _supplierId = e?.supplierId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _unitCtrl.dispose();
    _unitCostCtrl.dispose();
    _stockCtrl.dispose();
    _safetyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = widget.state.suppliers;
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Material' : 'Add Material'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _skuCtrl,
                  decoration: const InputDecoration(labelText: 'SKU'),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _unitCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Unit (e.g. kg, pcs)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _unitCostCtrl,
                  decoration: const InputDecoration(labelText: 'Unit Cost'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (double.tryParse(v) == null) return 'Invalid number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _stockCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Current Stock'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _safetyCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Safety Stock'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _supplierId,
                  decoration: const InputDecoration(labelText: 'Supplier'),
                  items: suppliers
                      .map((s) =>
                          DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _supplierId = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'Update' : 'Add'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final material = RawMaterial(
        id: widget.existing?.id ?? '',
        name: _nameCtrl.text.trim(),
        sku: _skuCtrl.text.trim(),
        unit: _unitCtrl.text.trim(),
        unitCost: double.parse(_unitCostCtrl.text.trim()),
        supplierId: _supplierId ?? '',
        currentStock: int.tryParse(_stockCtrl.text.trim()) ?? 0,
        safetyStock: int.tryParse(_safetyCtrl.text.trim()) ?? 0,
      );
      if (_isEdit) {
        await widget.state.updateRawMaterial(material);
      } else {
        await widget.state.addRawMaterial(material);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEdit ? 'Material updated' : 'Material added')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
