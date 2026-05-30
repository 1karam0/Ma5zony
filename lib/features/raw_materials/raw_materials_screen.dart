import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/raw_material.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';
import 'package:ma5zony/widgets/zoho_patterns.dart';
import 'package:ma5zony/features/onboarding/tour_targets.dart';

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
              KeyedSubtree(
                key: TourTargets.instance.keyFor('page:rawmaterials.add'),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Material'),
                  onPressed: () => _showFormDialog(context, state),
                ),
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

  // Inline new-supplier creation
  bool _creatingNewSupplier = false;
  final _newSupplierNameCtrl = TextEditingController();
  final _newSupplierEmailCtrl = TextEditingController();

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
    _newSupplierNameCtrl.dispose();
    _newSupplierEmailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = widget.state.suppliers;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.science_outlined,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isEdit ? 'Edit Material' : 'New Raw Material',
                    style: AppTextStyles.h3),
                const SizedBox(height: 2),
                Text(
                  _isEdit
                      ? 'Update unit cost, stock and supplier for this input.'
                      : 'Track an input you purchase and consume in production.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.textSecondary,
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ZohoFormSection(
                  title: 'Basic Information',
                  subtitle: 'Identify this raw material in your catalog.',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _skuCtrl,
                            decoration:
                                const InputDecoration(labelText: 'SKU *'),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _nameCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Name *'),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _uom,
                      decoration: const InputDecoration(
                          labelText: 'Unit of Measure *'),
                      items: _kUomOptions
                          .map((u) =>
                              DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (v) => setState(() => _uom = v ?? 'units'),
                    ),
                  ],
                ),
                ZohoFormSection(
                  title: 'Pricing & Inventory',
                  subtitle:
                      'Unit cost feeds BOM cost. Safety stock triggers reorders.',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _unitCostCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Unit Cost *',
                              prefixText: 'EGP ',
                              helperText: 'Price you pay per 1 unit/UoM',
                              helperMaxLines: 2,
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              if (double.tryParse(v) == null) {
                                return 'Invalid number';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _stockCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Current Stock',
                              helperText: 'Quantity on hand right now',
                              helperMaxLines: 2,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _safetyCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Safety Stock',
                              helperText: 'Reorder when stock hits this level',
                              helperMaxLines: 2,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ZohoFormSection(
                  title: 'Supply Chain',
                  subtitle:
                      'Who delivers this material and how long shipping takes.',
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: _creatingNewSupplier
                              ? _buildNewSupplierInline()
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    DropdownButtonFormField<String>(
                                      value: _supplierId,
                                      decoration: const InputDecoration(
                                          labelText: 'Supplier'),
                                      hint: const Text('Select supplier'),
                                      items: [
                                        ...suppliers.map((s) =>
                                            DropdownMenuItem(
                                                value: s.id,
                                                child: Text(s.name))),
                                        const DropdownMenuItem(
                                          value: '__new__',
                                          child: Row(
                                            children: [
                                              Icon(Icons.add_circle_outline,
                                                  size: 16,
                                                  color: AppColors.primary),
                                              SizedBox(width: 6),
                                              Text('New supplier…',
                                                  style: TextStyle(
                                                      color:
                                                          AppColors.primary,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ],
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v == '__new__') {
                                          setState(() {
                                            _supplierId = null;
                                            _creatingNewSupplier = true;
                                          });
                                        } else {
                                          setState(() => _supplierId = v);
                                        }
                                      },
                                      validator: null,
                                    ),
                                  ],
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _leadTimeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Lead Time',
                              hintText: 'Days to receive',
                              suffixText: 'days',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.isEmpty) return null;
                              if (int.tryParse(v) == null) {
                                return 'Whole number';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(_isEdit ? 'Save Changes' : 'Add Material'),
        ),
      ],
    );
  }

  Widget _buildNewSupplierInline() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.add_business_outlined,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('New Supplier',
                  style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _creatingNewSupplier = false),
                child: const Icon(Icons.close,
                    size: 14, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _newSupplierNameCtrl,
            decoration: const InputDecoration(
                labelText: 'Supplier Name *', isDense: true),
            validator: (v) => _creatingNewSupplier &&
                    (v == null || v.trim().isEmpty)
                ? 'Required'
                : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _newSupplierEmailCtrl,
            decoration: const InputDecoration(
                labelText: 'Email (optional)', isDense: true),
            keyboardType: TextInputType.emailAddress,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // If the user filled in a new supplier inline, create it first.
      String? resolvedSupplierId = _supplierId;
      if (_creatingNewSupplier &&
          _newSupplierNameCtrl.text.trim().isNotEmpty) {
        final newSupplier = Supplier(
          id: '',
          name: _newSupplierNameCtrl.text.trim(),
          contactEmail: _newSupplierEmailCtrl.text.trim(),
          typicalLeadTimeDays:
              int.tryParse(_leadTimeCtrl.text.trim()) ?? 0,
          suppliedRawMaterialIds: const [],
        );
        final saved = await widget.state.addSupplier(newSupplier);
        resolvedSupplierId = saved.id;
      }

      final material = RawMaterial(
        id: widget.existing?.id ?? '',
        name: _nameCtrl.text.trim(),
        sku: _skuCtrl.text.trim(),
        unit: _uom,
        unitOfMeasure: _uom,
        unitCost: double.tryParse(_unitCostCtrl.text.trim()) ?? 0.0,
        supplierId: resolvedSupplierId,
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
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
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
