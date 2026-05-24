import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/warehouse.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class WarehousesScreen extends StatelessWidget {
  const WarehousesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final warehouses = state.warehouses;
    final products = state.products;

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalStock = warehouses.fold<int>(0, (sum, w) => sum + w.totalStock);
    final totalValue = state.totalStockValue;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI row
          Row(
            children: [
              Expanded(
                child: KPICard(
                  title: 'Total Facilities',
                  value: '${warehouses.length}',
                  icon: Icons.warehouse,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Total Units Stored',
                  value: '$totalStock',
                  icon: Icons.inventory_2,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Total Stock Value',
                  value: 'EGP ${totalValue.toStringAsFixed(0)}',
                  icon: Icons.monetization_on,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Low Stock Alerts',
                  value: '${state.lowStockItems}',
                  icon: Icons.warning,
                  color: AppColors.warning,
                  isAlert: state.lowStockItems > 0,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          SectionHeader(
            title: 'Warehouses',
            actions: [
              ElevatedButton.icon(
                onPressed: () => _showAddWarehouseDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Warehouse'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),

          if (warehouses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.warehouse_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No warehouses yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
                    SizedBox(height: 8),
                    Text('Add your first warehouse to get started.', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            )
          else
            Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Warehouse Name')),
                  DataColumn(label: Text('Location')),
                  DataColumn(label: Text('Total Stock')),
                  DataColumn(label: Text('SKUs Stored')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: warehouses.map((w) {
                  final skuCount = products
                      .where((p) => p.warehouseId == w.id)
                      .length;
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          w.name,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${w.city}, ${w.country}'),
                            if ((w.address ?? '').trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 240),
                                  child: Text(
                                    w.address!.split('\n').first,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.label.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      DataCell(Text('${w.totalStock} units')),
                      DataCell(Text('$skuCount SKUs')),
                      const DataCell(StatusChip('Active')),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.inventory_2_outlined,
                                  size: 20),
                              onPressed: () => showDialog(
                                context: context,
                                builder: (_) =>
                                    _AssignProductsDialog(warehouse: w),
                              ),
                              tooltip: 'Manage Products',
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _showWarehouseDialog(context, w),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                size: 20,
                                color: AppColors.error,
                              ),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Warehouse'),
                                    content: Text(
                                      'Delete "${w.name}"? This cannot be undone.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Delete',
                                            style: TextStyle(
                                                color: AppColors.error)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && context.mounted) {
                                  try {
                                    await context
                                        .read<AppState>()
                                        .deleteWarehouse(w.id);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(duration: const Duration(seconds: 3), content: Text('Failed to delete warehouse: $e')),
                                      );
                                    }
                                  }
                                }
                              },
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Per-warehouse product breakdown
          ...warehouses.map((w) {
            final wProducts = products
                .where((p) => p.warehouseId == w.id)
                .toList();
            if (wProducts.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${w.name} — Product Breakdown', style: AppTextStyles.h3),
                const SizedBox(height: 12),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('SKU')),
                        DataColumn(label: Text('Product')),
                        DataColumn(label: Text('Category')),
                        DataColumn(label: Text('Stock')),
                      ],
                      rows: wProducts.map((p) {
                        return DataRow(
                          cells: [
                            DataCell(Text(p.sku)),
                            DataCell(Text(p.name)),
                            DataCell(Text(p.category)),
                            DataCell(Text('${p.currentStock}')),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          }),
        ],
      ),
    );
  }

  void _showAddWarehouseDialog(BuildContext context) {
    _showWarehouseDialog(context, null);
  }

  void _showWarehouseDialog(BuildContext context, Warehouse? existing) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final cityCtrl = TextEditingController(text: existing?.city ?? '');
    final countryCtrl = TextEditingController(text: existing?.country ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');
    final formKey = GlobalKey<FormState>();
    final isEdit = existing != null;
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Warehouse' : 'Add New Warehouse'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Warehouse Name'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: cityCtrl,
                          decoration: const InputDecoration(labelText: 'City'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: countryCtrl,
                          decoration: const InputDecoration(labelText: 'Country'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: addressCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Full Address (optional)',
                      hintText: 'e.g. 42 Industrial Road, Zone 5',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final navigator = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(ctx);
              final appState = context.read<AppState>();
              final warehouse = Warehouse(
                id: existing?.id ?? '',
                name: nameCtrl.text.trim(),
                city: cityCtrl.text.trim(),
                country: countryCtrl.text.trim(),
                address: addressCtrl.text.trim().isEmpty
                    ? null
                    : addressCtrl.text.trim(),
                totalStock: existing?.totalStock ?? 0,
              );
              try {
                if (isEdit) {
                  await appState.updateWarehouse(warehouse);
                } else {
                  await appState.addWarehouse(warehouse);
                }
                navigator.pop();
                messenger.showSnackBar(SnackBar(
                  duration: const Duration(seconds: 3),
                  content: Text(isEdit
                      ? 'Warehouse updated successfully'
                      : 'Warehouse added successfully'),
                  backgroundColor: AppColors.success,
                ));
              } catch (e) {
                messenger.showSnackBar(SnackBar(
                  duration: const Duration(seconds: 3),
                  content: Text('Error: $e'),
                  backgroundColor: AppColors.error,
                ));
              }
            },
            child: Text(isEdit ? 'Save Changes' : 'Add Warehouse'),
          ),
        ],
      ),
    );
  }
}

// ─── Assign Products Dialog ───────────────────────────────────────────────────

class _AssignProductsDialog extends StatefulWidget {
  final Warehouse warehouse;
  const _AssignProductsDialog({required this.warehouse});

  @override
  State<_AssignProductsDialog> createState() => _AssignProductsDialogState();
}

class _AssignProductsDialogState extends State<_AssignProductsDialog> {
  final Set<String> _selected = {};
  String _search = '';
  bool _saving = false;
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final allProducts = state.products;

    if (!_seeded) {
      // Pre-check products already assigned to this warehouse
      for (final p in allProducts) {
        if (p.warehouseId == widget.warehouse.id) _selected.add(p.id);
      }
      _seeded = true;
    }

    // Show all products. Products assigned to other warehouses appear with a
    // "Currently at [Other Warehouse]" badge and can still be selected to move.
    final visible = allProducts.where((p) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q);
    }).toList();

    final warehousesById = {for (final w in state.warehouses) w.id: w};

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
            child: const Icon(Icons.inventory_2_outlined,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Manage Products', style: AppTextStyles.h3),
                const SizedBox(height: 2),
                Text(
                  widget.warehouse.name,
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
        width: 560,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select which products are stored in this warehouse. Selecting a product currently at another warehouse will move it here after confirmation.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search by name or SKU',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: visible.isEmpty
                      ? null
                      : () => setState(
                          () => _selected.addAll(visible.map((p) => p.id))),
                  child: const Text('Select all visible'),
                ),
                TextButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => setState(_selected.clear),
                  child: const Text('Clear'),
                ),
                const Spacer(),
                Text('${_selected.length} selected',
                    style: AppTextStyles.bodySmall),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        allProducts.isEmpty
                            ? 'No products in inventory yet. Add or import products first.'
                            : 'No products match your search.',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, i) {
                        final p = visible[i];
                        final checked = _selected.contains(p.id);
                        final atOther = p.warehouseId != null &&
                            p.warehouseId != widget.warehouse.id;
                        final otherName = atOther
                            ? (warehousesById[p.warehouseId]?.name ?? 'another warehouse')
                            : null;
                        return CheckboxListTile(
                          dense: true,
                          value: checked,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selected.add(p.id);
                            } else {
                              _selected.remove(p.id);
                            }
                          }),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (atOther) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: AppColors.warning
                                            .withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    'At $otherName',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.warning),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                              '${p.sku} · ${p.category} · ${p.currentStock} in stock'),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
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
          onPressed: _saving
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  final appState = context.read<AppState>();

                  // Detect moves from another warehouse so we can ask the
                  // user before reassigning. Pure additions / unassigns skip
                  // the confirmation.
                  final moves = allProducts.where((p) =>
                      _selected.contains(p.id) &&
                      p.warehouseId != null &&
                      p.warehouseId != widget.warehouse.id).toList();
                  if (moves.isNotEmpty) {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Move products?'),
                        content: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                  '${moves.length} product${moves.length == 1 ? '' : 's'} will be moved to "${widget.warehouse.name}":'),
                              const SizedBox(height: 8),
                              ...moves.take(8).map((p) {
                                final from = warehousesById[p.warehouseId]?.name ?? 'another warehouse';
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Text('• ${p.name} — from $from',
                                      style: AppTextStyles.bodySmall),
                                );
                              }),
                              if (moves.length > 8)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('+ ${moves.length - 8} more…',
                                      style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.textSecondary)),
                                ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Move'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                  }

                  setState(() => _saving = true);

                  // Diff: products to add to this warehouse vs to unassign
                  final currentlyAssigned = allProducts
                      .where((p) => p.warehouseId == widget.warehouse.id)
                      .map((p) => p.id)
                      .toSet();
                  final toAssign = _selected
                      .where((id) => !currentlyAssigned.contains(id))
                      .toList();
                  final toUnassign = currentlyAssigned
                      .where((id) => !_selected.contains(id))
                      .toList();

                  try {
                    if (toAssign.isNotEmpty) {
                      await appState.assignProductsToWarehouse(
                          widget.warehouse.id, toAssign);
                    }
                    if (toUnassign.isNotEmpty) {
                      await appState.assignProductsToWarehouse(
                          null, toUnassign);
                    }
                    navigator.pop();
                    messenger.showSnackBar(SnackBar(
                      duration: const Duration(seconds: 3),
                      content: Text(
                          'Saved: ${toAssign.length} assigned, ${toUnassign.length} unassigned'),
                      backgroundColor: AppColors.success,
                    ));
                  } catch (e) {
                    if (mounted) setState(() => _saving = false);
                    messenger.showSnackBar(SnackBar(
                      duration: const Duration(seconds: 3),
                      content: Text('Error: $e'),
                      backgroundColor: AppColors.error,
                    ));
                  }
                },
          child: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Save Assignments'),
        ),
      ],
    );
  }
}
