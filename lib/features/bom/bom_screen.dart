import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';
import 'package:ma5zony/widgets/zoho_patterns.dart';
import 'package:ma5zony/features/onboarding/tour_targets.dart';

const _kUomOptions = ['units', 'g', 'kg', 'm', 'cm', 'L', 'mL', 'pcs'];

class BomScreen extends StatefulWidget {
  const BomScreen({super.key});

  @override
  State<BomScreen> createState() => _BomScreenState();
}

class _BomScreenState extends State<BomScreen> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final products = {for (final p in state.products) p.id: p.name};
    final rawMaterials = {for (final m in state.rawMaterials) m.id: m};

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Bill of Materials',
            actions: [
              KeyedSubtree(
                key: TourTargets.instance.keyFor('page:bom.add'),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add BOM'),
                  onPressed: () => _showFormDialog(context, state),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Products that come directly from a supplier — shown as a
          // read-only summary. They don't need a BOM.
          () {
            final supplierProducts = state.products
                .where((p) =>
                    (p.manufacturerId == null || p.manufacturerId!.isEmpty) &&
                    p.supplierId != null &&
                    p.supplierId!.isNotEmpty)
                .toList();
            if (supplierProducts.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.infoBg.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.info.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_shipping_outlined,
                            size: 16, color: AppColors.info),
                        const SizedBox(width: 8),
                        Text(
                          'Supplier-sourced products (no BOM needed)',
                          style: AppTextStyles.body
                              .copyWith(fontWeight: FontWeight.w600, color: AppColors.info),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'These products arrive as finished goods from your supplier. '  
                      'No raw materials or manufacturing step — just set a unit cost and link a supplier.',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: supplierProducts
                          .map((p) => Chip(
                                avatar: const Icon(
                                    Icons.check_circle_outline,
                                    size: 14,
                                    color: AppColors.info),
                                label: Text(p.name,
                                    style: AppTextStyles.bodySmall),
                                backgroundColor:
                                    AppColors.surface,
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            );
          }(),
          if (state.boms.isEmpty)
            EmptyStateWidget(
              icon: Icons.account_tree_outlined,
              title: 'No Bills of Materials yet',
              description: 'Create BOMs to define the raw materials needed for each manufactured product.',
              primaryLabel: 'Add BOM',
              onPrimary: () => _showFormDialog(context, state),
            )
          else
            ...state.boms.map((bom) {
              final productName =
                  products[bom.finalProductId] ?? 'Unknown Product';
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: const Icon(Icons.list_alt, color: AppColors.primary),
                  title: Row(
                    children: [
                      Text(productName, style: AppTextStyles.h3),
                      const SizedBox(width: 10),
                      _ActiveBadge(isActive: bom.isActive),
                    ],
                  ),
                  subtitle:
                      Text('${bom.materials.length} material(s)',
                          style: AppTextStyles.bodySmall),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!bom.isActive)
                        TextButton.icon(
                          icon: const Icon(Icons.check_circle_outline,
                              size: 16, color: AppColors.success),
                          label: const Text('Set Active',
                              style: TextStyle(
                                  color: AppColors.success, fontSize: 12)),
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4)),
                          onPressed: () async {
                            try {
                              await context
                                  .read<AppState>()
                                  .setActiveBOM(bom.id, bom.finalProductId);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(duration: const Duration(seconds: 3), content: Text('Error: $e')),
                                );
                              }
                            }
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        tooltip: 'Edit',
                        onPressed: () =>
                            _showFormDialog(context, state, existing: bom),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 18),
                        tooltip: 'Delete',
                        color: AppColors.error,
                        onPressed: () => _confirmDelete(context, state, bom),
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Material')),
                          DataColumn(label: Text('Qty / Unit')),
                          DataColumn(label: Text('UoM')),
                          DataColumn(label: Text('Unit Cost')),
                          DataColumn(label: Text('Line Cost')),
                        ],
                        rows: bom.materials.map((line) {
                          final rm = rawMaterials[line.rawMaterialId];
                          final unitCost = rm?.unitCost ?? 0;
                          final lineCost = line.quantityPerUnit * unitCost;
                          return DataRow(cells: [
                            DataCell(Text(rm?.name ?? line.rawMaterialId)),
                            DataCell(Text('${line.quantityPerUnit}')),
                            DataCell(Text(line.unitOfMeasure)),
                            DataCell(Text('EGP ${unitCost.toStringAsFixed(2)}')),
                            DataCell(Text('EGP ${lineCost.toStringAsFixed(2)}')),
                          ]);
                        }).toList(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 16, right: 16, bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Est. cost per unit: EGP ${_totalCost(bom, rawMaterials).toStringAsFixed(2)}',
                            style: AppTextStyles.h3,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  double _totalCost(
      BillOfMaterials bom, Map<String, dynamic> rawMaterials) {
    double total = 0;
    for (final line in bom.materials) {
      final rm = rawMaterials[line.rawMaterialId];
      if (rm != null) {
        total += line.quantityPerUnit * (rm.unitCost as double);
      }
    }
    return total;
  }

  void _showFormDialog(BuildContext context, AppState state,
      {BillOfMaterials? existing}) {
    showDialog(
      context: context,
      builder: (_) =>
          _BomFormDialog(state: state, existing: existing),
    );
  }

  void _confirmDelete(BuildContext ctx, AppState state, BillOfMaterials bom) {
    final products = {for (final p in state.products) p.id: p.name};
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete BOM'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delete BOM for "${products[bom.finalProductId] ?? bom.id}"?'),
            if (bom.isActive) ...[
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
                        'This is the active BOM. Deleting it will disable raw material order creation for this product until a new BOM is set as active.',
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
                await state.deleteBOM(bom.id);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('BOM deleted'), duration: Duration(seconds: 3)),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(duration: const Duration(seconds: 3), content: Text('Error: $e')),
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

// ─── Active Badge ─────────────────────────────────────────────────────────────

class _ActiveBadge extends StatelessWidget {
  final bool isActive;
  const _ActiveBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.textSecondary;
    final label = isActive ? 'Active' : 'Inactive';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ─── BOM Form Dialog ──────────────────────────────────────────────────────────

class _SourcingBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  const _SourcingBadge(
      {required this.icon,
      required this.label,
      required this.color,
      required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _BomFormDialog extends StatefulWidget {
  final AppState state;
  final BillOfMaterials? existing;

  const _BomFormDialog({required this.state, this.existing});

  @override
  State<_BomFormDialog> createState() => _BomFormDialogState();
}

class _BomFormDialogState extends State<_BomFormDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _productId;
  /// One row per raw material — initialised in initState once we have access
  /// to widget.state.rawMaterials.
  late List<_MaterialLine> _lines;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _productId = widget.existing?.finalProductId;

    // Build one row for every raw material, pre-ticking those that are
    // already in the BOM (edit mode) and prefilling their qty/uom.
    final existingByMaterialId = <String, BomMaterial>{
      if (widget.existing != null)
        for (final m in widget.existing!.materials) m.rawMaterialId: m,
    };
    _lines = widget.state.rawMaterials.map((rm) {
      final existing = existingByMaterialId[rm.id];
      // Priority: 1) saved BOM line  2) unit already set on the raw material
      //           3) fallback 'units'
      final uom = existing != null && _kUomOptions.contains(existing.unitOfMeasure)
          ? existing.unitOfMeasure
          : _kUomOptions.contains(rm.unitOfMeasure)
              ? rm.unitOfMeasure
              : 'units';
      return _MaterialLine(
        materialId: rm.id,
        materialName: rm.name,
        included: existing != null,
        qtyCtrl: TextEditingController(
            text: existing != null ? '${existing.quantityPerUnit}' : '1'),
        uom: uom,
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.qtyCtrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.state.products;
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
            child: const Icon(Icons.account_tree_outlined,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isEdit ? 'Edit BOM' : 'Create BOM',
                    style: AppTextStyles.h3),
                const SizedBox(height: 2),
                Text(
                  'Define which raw materials are consumed to build one unit of this product.',
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
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ZohoFormSection(
                  title: 'Final Product',
                  subtitle: 'Only manufactured products are shown here. Supplier-sourced products (like grips) arrive ready-made and don\'t need a BOM.',
                  children: [
                    // Sourcing-route legend
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          _SourcingBadge(
                            icon: Icons.precision_manufacturing_outlined,
                            label: 'Manufactured',
                            color: AppColors.primary,
                            bg: AppColors.primaryLight,
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward,
                              size: 14, color: AppColors.textSubdued),
                          const SizedBox(width: 8),
                          Text('needs BOM + raw materials',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textSecondary)),
                          const SizedBox(width: 20),
                          _SourcingBadge(
                            icon: Icons.local_shipping_outlined,
                            label: 'From supplier',
                            color: AppColors.info,
                            bg: AppColors.infoBg,
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward,
                              size: 14, color: AppColors.textSubdued),
                          const SizedBox(width: 8),
                          Text('no BOM needed',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    () {
                      // Only manufactured products belong in a BOM.
                      final mfgProducts = products
                          .where((p) =>
                              p.manufacturerId != null &&
                              p.manufacturerId!.isNotEmpty)
                          .toList();
                      if (mfgProducts.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.warningBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.warning
                                    .withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  size: 16, color: AppColors.warning),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'No manufactured products found. Set a Manufacturer on the products that go through production.',
                                      style: AppTextStyles.bodySmall,
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        context.go('/products');
                                      },
                                      icon: const Icon(
                                          Icons.open_in_new,
                                          size: 14),
                                      label: const Text('Go to Products'),
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        foregroundColor: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return DropdownButtonFormField<String>(
                        initialValue: _productId,
                        decoration: const InputDecoration(
                            labelText: 'Final Product *'),
                        items: mfgProducts
                            .map((p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Row(
                                    children: [
                                      const Icon(
                                          Icons
                                              .precision_manufacturing_outlined,
                                          size: 14,
                                          color: AppColors.primary),
                                      const SizedBox(width: 8),
                                      Text(p.name),
                                    ],
                                  ),
                                ))
                            .toList(),
                        onChanged: _isEdit
                            ? null // can't change product on existing BOM
                            : (v) => setState(() => _productId = v),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Select a product' : null,
                      );
                    }(),
                  ],
                ),
                ZohoFormSection(
                  title: 'Materials',
                  subtitle: 'Tick every raw material this product needs. '  
                      'Fill in how much of each is used per unit produced.',
                  children: [
                    if (_lines.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warningBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 16, color: AppColors.warning),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'No raw materials added yet. Add the materials this product is built from.',
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      context.go('/raw-materials');
                                    },
                                    icon: const Icon(
                                        Icons.open_in_new,
                                        size: 14),
                                    label: const Text('Go to Raw Materials'),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      foregroundColor: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[  
                      // Column headers
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const SizedBox(width: 44), // checkbox col
                            Expanded(
                              flex: 4,
                              child: Text('MATERIAL',
                                  style: AppTextStyles.tableHeader),
                            ),
                            SizedBox(
                              width: 100,
                              child: Text('QTY / UNIT',
                                  style: AppTextStyles.tableHeader),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 110,
                              child: Text('UoM',
                                  style: AppTextStyles.tableHeader),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // One row per raw material
                      ..._lines.map((line) {
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 44,
                                child: Checkbox(
                                  value: line.included,
                                  onChanged: (v) => setState(
                                      () => line.included = v ?? false),
                                ),
                              ),
                              Expanded(
                                flex: 4,
                                child: Text(
                                  line.materialName,
                                  style: AppTextStyles.tableCell.copyWith(
                                    color: line.included
                                        ? AppColors.textPrimary
                                        : AppColors.textSubdued,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 100,
                                child: TextFormField(
                                  controller: line.qtyCtrl,
                                  enabled: line.included,
                                  decoration: const InputDecoration(
                                      isDense: true,
                                      hintText: '0'),
                                  keyboardType: TextInputType.number,
                                  validator: (v) {
                                    if (!line.included) return null;
                                    if (v == null || v.isEmpty) {
                                      return 'Required';
                                    }
                                    if ((double.tryParse(v) ?? 0) <= 0) {
                                      return '> 0';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 110,
                                child: DropdownButtonFormField<String>(
                                  value: line.uom,
                                  decoration: const InputDecoration(
                                      isDense: true),
                                  items: _kUomOptions
                                      .map((u) => DropdownMenuItem(
                                          value: u, child: Text(u)))
                                      .toList(),
                                  onChanged: line.included
                                      ? (v) => setState(
                                          () => line.uom = v ?? 'units')
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${_lines.where((l) => l.included).length} of ${_lines.length} material(s) included',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
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
              : Text(_isEdit ? 'Update BOM' : 'Create BOM'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final included = _lines.where((l) => l.included).toList();
    if (included.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tick at least one material'),
            duration: Duration(seconds: 3)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final bom = BillOfMaterials(
        id: widget.existing?.id ?? '',
        finalProductId: _productId!,
        isActive: widget.existing?.isActive ?? true,
        materials: included
            .map((l) => BomMaterial(
                  rawMaterialId: l.materialId,
                  quantityPerUnit: double.parse(l.qtyCtrl.text.trim()),
                  unitOfMeasure: l.uom,
                ))
            .toList(),
      );
      if (_isEdit) {
        await widget.state.updateBOM(bom);
      } else {
        await widget.state.addBOM(bom);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              duration: const Duration(seconds: 3),
              content: Text(_isEdit ? 'BOM updated' : 'BOM created')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              duration: const Duration(seconds: 3),
              content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// One row in the bulk-checklist. Exists for every raw material.
/// [included] = ticked by the user; only ticked rows are saved to the BOM.
class _MaterialLine {
  final String materialId;
  final String materialName;
  bool included;
  final TextEditingController qtyCtrl;
  String uom;

  _MaterialLine({
    required this.materialId,
    required this.materialName,
    this.included = false,
    required this.qtyCtrl,
    this.uom = 'units',
  });
}
