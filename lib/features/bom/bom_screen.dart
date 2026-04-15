import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

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
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.list_alt,
                        size: 48, color: AppColors.textSecondary),
                    SizedBox(height: 8),
                    Text('No BOMs defined yet',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else
            ...state.boms.map((bom) {
              final productName =
                  products[bom.finalProductId] ?? 'Unknown Product';
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: const Icon(Icons.list_alt, color: AppColors.primary),
                  title: Text(productName, style: AppTextStyles.h3),
                  subtitle:
                      Text('${bom.materials.length} material(s)',
                          style: AppTextStyles.bodySmall),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                          DataColumn(label: Text('Unit Cost')),
                          DataColumn(label: Text('Line Cost')),
                        ],
                        rows: bom.materials.map((line) {
                          final rm = rawMaterials[line.rawMaterialId];
                          final unitCost = rm?.unitCost ?? 0;
                          final lineCost =
                              line.quantityPerUnit * unitCost;
                          return DataRow(cells: [
                            DataCell(Text(rm?.name ?? line.rawMaterialId)),
                            DataCell(Text(
                                '${line.quantityPerUnit} ${rm?.unit ?? ''}')),
                            DataCell(Text('\$${unitCost.toStringAsFixed(2)}')),
                            DataCell(Text('\$${lineCost.toStringAsFixed(2)}')),
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
                            'Total per unit: \$${_totalCost(bom, rawMaterials).toStringAsFixed(2)}',
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
        content: Text(
            'Delete BOM for "${products[bom.finalProductId] ?? bom.id}"?'),
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
                    const SnackBar(content: Text('BOM deleted')),
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
        _lines.add(_MaterialLine(
          materialId: m.rawMaterialId,
          qtyCtrl: TextEditingController(text: '${m.quantityPerUnit}'),
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
      title: Text(_isEdit ? 'Edit BOM' : 'Create BOM'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _productId,
                  decoration:
                      const InputDecoration(labelText: 'Final Product'),
                  items: products
                      .map((p) =>
                          DropdownMenuItem(value: p.id, child: Text(p.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _productId = v),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Select a product' : null,
                ),
                const SizedBox(height: 16),
                Text('Materials', style: AppTextStyles.h3),
                const SizedBox(height: 8),
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
                        IconButton(
                          icon: const Icon(Icons.remove_circle,
                              color: AppColors.error),
                          onPressed: () => setState(() => _lines.removeAt(i)),
                        ),
                      ],
                    ),
                  );
                }),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Material Line'),
                  onPressed: () => setState(() => _lines.add(_MaterialLine(
                      qtyCtrl: TextEditingController(text: '1')))),
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
              : Text(_isEdit ? 'Update' : 'Create'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one material')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final bom = BillOfMaterials(
        id: widget.existing?.id ?? '',
        finalProductId: _productId!,
        materials: _lines
            .map((l) => BomMaterial(
                  rawMaterialId: l.materialId!,
                  quantityPerUnit: double.parse(l.qtyCtrl.text.trim()),
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
          SnackBar(content: Text(_isEdit ? 'BOM updated' : 'BOM created')),
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

class _MaterialLine {
  String? materialId;
  final TextEditingController qtyCtrl;

  _MaterialLine({this.materialId, required this.qtyCtrl});
}
