import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/raw_material.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

const _kUomOptions = ['units', 'g', 'kg', 'm', 'cm', 'L', 'mL', 'pcs'];

class RawMaterialsScreen extends StatefulWidget {
  const RawMaterialsScreen({super.key});

  @override
  State<RawMaterialsScreen> createState() => _RawMaterialsScreenState();
}

class _RawMaterialsScreenState extends State<RawMaterialsScreen> {
  String _search = '';
  bool _filterNoSupplier = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final suppliers = {for (final s in state.suppliers) s.id: s.name};

    final materials = state.rawMaterials.where((m) {
      if (_filterNoSupplier && m.supplierId != null && m.supplierId!.isNotEmpty) {
        return false;
      }
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return m.name.toLowerCase().contains(q) ||
          m.sku.toLowerCase().contains(q);
    }).toList();

    final totalMaterials = state.rawMaterials.length;
    final lowStock =
        state.rawMaterials.where((m) => m.currentStock <= m.safetyStock).length;
    final totalValue = state.rawMaterials.fold<double>(
        0, (sum, m) => sum + m.currentStock * m.unitCost);
    final unlinked =
        state.rawMaterials.where((m) => m.supplierId == null || m.supplierId!.isEmpty).length;

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
                  value: 'EGP ${totalValue.toStringAsFixed(0)}',
                  icon: Icons.attach_money,
                ),
              ),
              SizedBox(
                width: 200,
                child: KPICard(
                  title: 'No Supplier',
                  value: '$unlinked',
                  icon: Icons.link_off,
                  color: unlinked > 0 ? AppColors.warning : AppColors.success,
                  isAlert: unlinked > 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Search + filter row
          Row(
            children: [
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
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('No Supplier'),
                avatar: const Icon(Icons.link_off, size: 16),
                selected: _filterNoSupplier,
                selectedColor: AppColors.warning.withValues(alpha: 0.15),
                checkmarkColor: AppColors.warning,
                onSelected: (v) => setState(() => _filterNoSupplier = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (materials.isEmpty)
            EmptyStateWidget(
              icon: Icons.category_outlined,
              title: _filterNoSupplier
                  ? 'All materials have a supplier'
                  : 'No raw materials yet',
              description: _filterNoSupplier
                  ? 'Every raw material is linked to a supplier.'
                  : 'Add raw materials to track stock and link them to Bills of Materials.',
              primaryLabel: _filterNoSupplier ? null : 'Add Material',
              onPrimary: _filterNoSupplier
                  ? null
                  : () => _showFormDialog(context, state),
            )
          else
          Card(
            child: HorizontallyScrollableTable(
              child: DataTable(
                columns: [
                  DataColumn(label: Text('NAME', style: AppTextStyles.tableHeader)),
                  DataColumn(label: Text('SKU', style: AppTextStyles.tableHeader)),
                  DataColumn(label: Text('UNIT', style: AppTextStyles.tableHeader)),
                  DataColumn(label: Text('LEAD TIME', style: AppTextStyles.tableHeader)),
                  DataColumn(label: Text('UNIT COST', style: AppTextStyles.tableHeader), numeric: true),
                  DataColumn(label: Text('STOCK', style: AppTextStyles.tableHeader), numeric: true),
                  DataColumn(label: Text('SAFETY STOCK', style: AppTextStyles.tableHeader), numeric: true),
                  DataColumn(label: Text('SUPPLIER', style: AppTextStyles.tableHeader)),
                  DataColumn(label: Text('ACTIONS', style: AppTextStyles.tableHeader)),
                ],
                rows: materials.map((m) {
                  final isLow = m.currentStock <= m.safetyStock;
                  final supplierName = suppliers[m.supplierId];
                  return DataRow(
                    color: AppColors.dataRowColor,
                    cells: [
                    DataCell(Text(m.name, style: AppTextStyles.tableCell.copyWith(fontWeight: FontWeight.w600))),
                    DataCell(Text(m.sku, style: AppTextStyles.tableCell)),
                    DataCell(Text(m.unitOfMeasure, style: AppTextStyles.tableCell)),
                    DataCell(Text(
                      m.leadTimeDays > 0 ? '${m.leadTimeDays}d' : '—',
                      style: AppTextStyles.tableCell,
                    )),
                    DataCell(Text('EGP ${m.unitCost.toStringAsFixed(2)}', style: AppTextStyles.tableNum)),
                    DataCell(Text(
                      '${m.currentStock}',
                      style: AppTextStyles.tableNum.copyWith(
                        color: isLow ? AppColors.error : null,
                        fontWeight: isLow ? FontWeight.bold : null,
                      ),
                    )),
                    DataCell(Text('${m.safetyStock}', style: AppTextStyles.tableNum)),
                    DataCell(
                      supplierName != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.infoBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(supplierName,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.info,
                                      fontWeight: FontWeight.w600)),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('No supplier',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.warning,
                                      fontWeight: FontWeight.w600)),
                            ),
                    ),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Edit',
                          color: AppColors.textSecondary,
                          onPressed: () =>
                              _showFormDialog(context, state, existing: m),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
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
    final inBom = state.boms
        .any((b) => b.materials.any((line) => line.rawMaterialId == m.id));
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete Material'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delete "${m.name}"? This cannot be undone.'),
            if (inBom) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: AppColors.warning, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This material is used in one or more Bills of Materials. Deleting it will remove it from those BOMs.',
                        style: TextStyle(fontSize: 13, color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
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
  late final TextEditingController _unitCostCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _safetyCtrl;
  late final TextEditingController _leadTimeCtrl;
  String? _supplierId;
  String _uom = 'units';
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _skuCtrl = TextEditingController(text: e?.sku ?? '');
    _unitCostCtrl =
        TextEditingController(text: e != null ? '${e.unitCost}' : '');
    _stockCtrl =
        TextEditingController(text: e != null ? '${e.currentStock}' : '0');
    _safetyCtrl =
        TextEditingController(text: e != null ? '${e.safetyStock}' : '0');
    _leadTimeCtrl =
        TextEditingController(text: e != null ? '${e.leadTimeDays}' : '0');
    _supplierId = e?.supplierId;
    final existingUom = e?.unitOfMeasure ?? 'units';
    _uom = _kUomOptions.contains(existingUom) ? existingUom : 'units';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _unitCostCtrl.dispose();
    _stockCtrl.dispose();
    _safetyCtrl.dispose();
    _leadTimeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = widget.state.suppliers;
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Material' : 'Add Material'),
      content: SizedBox(
        width: 420,
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
                DropdownButtonFormField<String>(
                  value: _uom,
                  decoration: const InputDecoration(labelText: 'Unit of Measure'),
                  items: _kUomOptions
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) => setState(() => _uom = v ?? 'units'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _unitCostCtrl,
                  decoration: const InputDecoration(labelText: 'Unit Cost (EGP)'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (double.tryParse(v) == null) return 'Invalid number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stockCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Current Stock'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _safetyCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Safety Stock'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _leadTimeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lead Time (days)',
                    hintText: 'Days to receive from supplier',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return null;
                    if (int.tryParse(v) == null) return 'Enter a whole number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _supplierId,
                  decoration: const InputDecoration(labelText: 'Supplier'),
                  hint: const Text('Select supplier'),
                  items: suppliers
                      .map((s) =>
                          DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _supplierId = v),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Select a supplier' : null,
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
        unit: _uom,
        unitOfMeasure: _uom,
        unitCost: double.parse(_unitCostCtrl.text.trim()),
        supplierId: _supplierId,
        currentStock: int.tryParse(_stockCtrl.text.trim()) ?? 0,
        safetyStock: int.tryParse(_safetyCtrl.text.trim()) ?? 0,
        leadTimeDays: int.tryParse(_leadTimeCtrl.text.trim()) ?? 0,
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
