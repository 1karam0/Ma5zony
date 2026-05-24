import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';
import 'package:ma5zony/widgets/zoho_patterns.dart';

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
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add BOM'),
                onPressed: () => _showFormDialog(context, state),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (state.boms.isEmpty)
            EmptyStateWidget(
              icon: Icons.account_tree_outlined,
              title: 'No Bills of Materials yet',
              description: 'Create BOMs to define the raw materials needed for each product.',
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
  final List<_MaterialLine> _lines = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _productId = widget.existing!.finalProductId;
      for (final m in widget.existing!.materials) {
        final uom = _kUomOptions.contains(m.unitOfMeasure)
            ? m.unitOfMeasure
            : 'units';
        _lines.add(_MaterialLine(
          materialId: m.rawMaterialId,
          qtyCtrl: TextEditingController(text: '${m.quantityPerUnit}'),
          uom: uom,
        ));
      }
    }
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
    final rawMaterials = widget.state.rawMaterials;
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
                  subtitle: 'Pick the manufactured product this recipe builds.',
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _productId,
                      decoration: const InputDecoration(
                          labelText: 'Final Product *'),
                      items: products
                          .map((p) => DropdownMenuItem(
                              value: p.id, child: Text(p.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _productId = v),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Select a product' : null,
                    ),
                  ],
                ),
                ZohoFormSection(
                  title: 'Materials',
                  subtitle:
                      'Quantity per unit + unit of measure. Used to generate raw-material orders.',
                  children: [
                    ..._lines.asMap().entries.map((entry) {
                      final i = entry.key;
                      final line = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                initialValue: line.materialId,
                                decoration: const InputDecoration(
                                    labelText: 'Material', isDense: true),
                                items: rawMaterials
                                    .map((m) => DropdownMenuItem(
                                        value: m.id, child: Text(m.name)))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => line.materialId = v),
                                validator: (v) =>
                                    v == null ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: line.qtyCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Qty/Unit', isDense: true),
                                keyboardType: TextInputType.number,
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'Required';
                                  if (double.tryParse(v) == null) {
                                    return 'Invalid';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: DropdownButtonFormField<String>(
                                initialValue: line.uom,
                                decoration: const InputDecoration(
                                    labelText: 'UoM', isDense: true),
                                items: _kUomOptions
                                    .map((u) => DropdownMenuItem(
                                        value: u, child: Text(u)))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => line.uom = v ?? 'units'),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove material',
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: AppColors.error),
                              onPressed: () =>
                                  setState(() => _lines.removeAt(i)),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (_lines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No materials yet. Add one below.',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Material Line'),
                        onPressed: () => setState(() => _lines.add(_MaterialLine(
                            qtyCtrl: TextEditingController(text: '1')))),
                      ),
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
              : Text(_isEdit ? 'Update BOM' : 'Create BOM'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one material'), duration: Duration(seconds: 3)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final bom = BillOfMaterials(
        id: widget.existing?.id ?? '',
        finalProductId: _productId!,
        isActive: widget.existing?.isActive ?? true,
        materials: _lines
            .map((l) => BomMaterial(
                  rawMaterialId: l.materialId!,
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
          SnackBar(duration: const Duration(seconds: 3), content: Text(_isEdit ? 'BOM updated' : 'BOM created')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 3), content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _MaterialLine {
  String? materialId;
  final TextEditingController qtyCtrl;
  String uom;

  _MaterialLine({this.materialId, required this.qtyCtrl, this.uom = 'units'});
}
