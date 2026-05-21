import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _search = '';
  String _statusFilter = 'All'; // All | OK | Low | Critical

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final suppliers = {for (final s in state.suppliers) s.id: s.name};
    final manufacturers = {for (final m in state.manufacturers) m.id: m.name};
    final bomMap = {for (final b in state.boms) b.finalProductId: b};

    final recs = {for (final r in state.recommendations) r.productId: r};

    final products = state.products.where((p) {
      // Text search filter
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!p.name.toLowerCase().contains(q) &&
            !p.sku.toLowerCase().contains(q) &&
            !p.category.toLowerCase().contains(q)) {
          return false;
        }
      }
      // Status filter
      if (_statusFilter != 'All') {
        final status = p.currentStock == 0
            ? 'Critical'
            : (recs.containsKey(p.id) ? 'Low' : 'OK');
        if (status != _statusFilter) return false;
      }
      return true;
    }).toList();

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Low-stock alert banner
          Builder(builder: (context) {
            final lowStockCount = state.recommendations
                .where(
                    (r) => r.status == 'Critical' || r.status == 'Order Now')
                .length;
            if (lowStockCount == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: AlertBanner(
                severity: AlertSeverity.error,
                title: '$lowStockCount item(s) critically low or at zero stock',
                message: 'Review your replenishment recommendations and create purchase orders.',
                action: TextButton(
                  onPressed: () => context.go('/replenishment'),
                  child: const Text('View Replenishment'),
                ),
              ),
            );
          }),

          SectionHeader(
            title: 'Product Inventory',
            actions: [
              SizedBox(
                width: 220,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search products...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () => _showImportDialog(context),
                icon: const Icon(Icons.cloud_download),
                label: const Text('Import from Shopify'),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => _showAddProductDialog(context, state),
                icon: const Icon(Icons.add),
                label: const Text('Add Product'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),

          // Status filter chips
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              children: ['All', 'OK', 'Low', 'Critical'].map((filter) {
                final isActive = _statusFilter == filter;
                final chipColor = filter == 'Critical'
                    ? AppColors.error
                    : filter == 'Low'
                        ? AppColors.warning
                        : filter == 'OK'
                            ? AppColors.success
                            : AppColors.primary;
                return FilterChip(
                  label: Text(filter),
                  selected: isActive,
                  onSelected: (_) => setState(() => _statusFilter = filter),
                  selectedColor: chipColor.withValues(alpha: 0.15),
                  checkmarkColor: chipColor,
                  labelStyle: TextStyle(
                    color: isActive ? chipColor : AppColors.textSecondary,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 12,
                  ),
                  side: BorderSide(
                    color: isActive
                        ? chipColor.withValues(alpha: 0.5)
                        : AppColors.border,
                  ),
                );
              }).toList(),
            ),
          ),

          if (products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: state.products.isEmpty
                  // No products at all — show onboarding CTA
                  ? EmptyStateWidget(
                      icon: Icons.inventory_2_outlined,
                      title: 'No products yet',
                      description:
                          'Add products manually or import them directly from your Shopify store.',
                      primaryLabel: 'Import from Shopify',
                      onPrimary: () => context.go('/integrations'),
                      secondaryLabel: 'Add Manually',
                      onSecondary: () => _showAddProductDialog(context, state),
                    )
                  // Products exist but filter gives 0 — show filter-empty state
                  : EmptyStateWidget(
                      icon: Icons.filter_list_off,
                      title: 'No products match "$_statusFilter"',
                      description:
                          'Try a different filter or clear your search.',
                      primaryLabel: 'Clear Filters',
                      onPrimary: () => setState(() {
                        _search = '';
                        _statusFilter = 'All';
                      }),
                    ),
            )
          else
            Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(cardColor: Colors.white),
              child: PaginatedDataTable(
                header: Text(
                  '${products.length} Products',
                  style: AppTextStyles.h3,
                ),
                columns: [
                  DataColumn(label: Text('NAME / SKU', style: AppTextStyles.tableHeader)),
                  DataColumn(label: Text('CATEGORY', style: AppTextStyles.tableHeader)),
                  DataColumn(label: Text('STOCK', style: AppTextStyles.tableHeader), numeric: true),
                  DataColumn(label: Text('UNIT COST', style: AppTextStyles.tableHeader), numeric: true),
                  DataColumn(label: Text('SUPPLY CHAIN', style: AppTextStyles.tableHeader)),
                  DataColumn(label: Text('STATUS', style: AppTextStyles.tableHeader)),
                  DataColumn(label: Text('ACTIONS', style: AppTextStyles.tableHeader)),
                ],
                source: _ProductDataSource(
                  products: products,
                  supplierMap: suppliers,
                  manufacturerMap: manufacturers,
                  bomMap: bomMap,
                  rawMaterials: state.rawMaterials,
                  rawMaterialSupplierMap: suppliers,
                  context: context,
                ),
                rowsPerPage: 10,
                showCheckboxColumn: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    showDialog(context: context, builder: (ctx) => const _ImportDialog());
  }

  void _showAddProductDialog(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (ctx) => _AddProductDialog(
        suppliers: state.suppliers,
        manufacturers: state.manufacturers,
        warehouses: state.warehouses,
      ),
    );
  }
}

// ─── DataTableSource ──────────────────────────────────────────────────────────

class _ProductDataSource extends DataTableSource {
  final List<Product> products;
  final Map<String, String> supplierMap;
  final Map<String, String> manufacturerMap;
  final Map<String, BillOfMaterials> bomMap;
  final List rawMaterials;
  final Map<String, String> rawMaterialSupplierMap;
  final BuildContext context;

  _ProductDataSource({
    required this.products,
    required this.supplierMap,
    required this.manufacturerMap,
    required this.bomMap,
    required this.rawMaterials,
    required this.rawMaterialSupplierMap,
    required this.context,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= products.length) return null;
    final p = products[index];

    final recs = context
        .read<AppState>()
        .recommendations;
    final recMap = {for (final r in recs) r.productId: r};

    // Corrected stock status logic:
    //   Critical = stock is exactly 0
    //   Low      = stock > 0 but below reorder point (has a recommendation)
    //   OK       = stock is healthy
    final status = p.currentStock == 0
        ? 'Critical'
        : (recMap.containsKey(p.id) ? 'Low' : 'OK');

    return DataRow(
      cells: [
        // Name + SKU
        DataCell(
          SizedBox(
            width: 260,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.tableCell
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  p.sku,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
        ),
        // Category
        DataCell(Text(p.category, style: AppTextStyles.tableCell)),
        // Stock (right-aligned via numeric: true on the column)
        DataCell(Text(
          '${p.currentStock}',
          style: AppTextStyles.tableNum,
          textAlign: TextAlign.right,
        )),
        // Unit Cost
        DataCell(Text(
          'EGP ${p.unitCost.toStringAsFixed(2)}',
          style: AppTextStyles.tableNum,
          textAlign: TextAlign.right,
        )),
        // Supply Chain Health
        DataCell(_SupplyChainCell(
          product: p,
          bomMap: bomMap,
          rawMaterials: rawMaterials,
          context: context,
        )),
        // Status
        DataCell(StatusChip(status)),
        // Actions
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () {
                  final st = context.read<AppState>();
                  showDialog(
                    context: context,
                    builder: (_) => _AddProductDialog(
                      suppliers: st.suppliers,
                      manufacturers: st.manufacturers,
                      warehouses: st.warehouses,
                      existingProduct: p,
                    ),
                  );
                },
                tooltip: 'Edit',
                color: AppColors.textSecondary,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppColors.error,
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Product'),
                      content: Text('Delete "${p.name}"? This cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete',
                              style: TextStyle(color: AppColors.error)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    try {
                      await context.read<AppState>().deleteProduct(p.id);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to delete: $e')),
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
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => products.length;
  @override
  int get selectedRowCount => 0;
}

// ─── Supply Chain Cell ────────────────────────────────────────────────────────

class _SupplyChainCell extends StatelessWidget {
  final Product product;
  final Map<String, BillOfMaterials> bomMap;
  final List rawMaterials;
  final BuildContext context;

  const _SupplyChainCell({
    required this.product,
    required this.bomMap,
    required this.rawMaterials,
    required this.context,
  });

  @override
  Widget build(BuildContext ctx) {
    final bom = bomMap[product.id];
    final hasBom = bom != null;

    // Supplier: at least one material in BOM has a supplier
    final hasSupplier = bom != null &&
        bom.materials.any((m) => rawMaterials.any(
            (r) => r.id == m.rawMaterialId &&
                r.supplierId != null &&
                (r.supplierId as String).isNotEmpty));

    final hasWarehouse =
        product.warehouseId != null && product.warehouseId!.isNotEmpty;

    // Determine the first missing step to direct user to
    String? fixPath;
    String? fixLabel;
    if (!hasBom) {
      fixPath = '/bom';
      fixLabel = 'Set up BOM';
    } else if (!hasSupplier) {
      fixPath = '/suppliers';
      fixLabel = 'Add Supplier';
    } else if (!hasWarehouse) {
      fixPath = '/warehouses';
      fixLabel = 'Assign Warehouse';
    }

    final allGood = hasBom && hasSupplier && hasWarehouse;

    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              _ChainBadge(label: 'BOM', ok: hasBom),
              const SizedBox(width: 4),
              _ChainBadge(label: 'Supplier', ok: hasSupplier),
              const SizedBox(width: 4),
              _ChainBadge(label: 'Warehouse', ok: hasWarehouse),
            ],
          ),
          if (!allGood && fixPath != null)
            InkWell(
              onTap: () => context.go(fixPath!),
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(fixLabel!,
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                    const Icon(Icons.arrow_forward_ios,
                        size: 8, color: AppColors.primary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChainBadge extends StatelessWidget {
  final String label;
  final bool ok;
  const _ChainBadge({required this.label, required this.ok});

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check : Icons.close, size: 9, color: color),
          const SizedBox(width: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

// ─── Import Dialog ────────────────────────────────────────────────────────────

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final Set<String> _selectedIds = {};
  List<Product> _shopifyProducts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    try {
      final appState = context.read<AppState>();
      final products = await appState.fetchShopifyProducts();
      if (mounted) {
        setState(() {
          _shopifyProducts = products;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import from Shopify'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Text(
                      'Failed to load products:\n$_error',
                      textAlign: TextAlign.center,
                    ),
                  )
                : _shopifyProducts.isEmpty
                    ? const Center(
                        child: Text(
                          'No products found in your Shopify store.\n'
                          'Make sure your store is connected.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
          children: [
            Row(
              children: [
                Checkbox(
                  value: _selectedIds.length == _shopifyProducts.length &&
                      _shopifyProducts.isNotEmpty,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedIds.addAll(
                          _shopifyProducts.map((p) => p.id),
                        );
                      } else {
                        _selectedIds.clear();
                      }
                    });
                  },
                ),
                const Text('Select All'),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _shopifyProducts.length,
                itemBuilder: (context, i) {
                  final p = _shopifyProducts[i];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      color: Colors.grey[200],
                      child: const Icon(Icons.image),
                    ),
                    title: Text(p.name),
                    subtitle: Text(
                      '${p.sku} - EGP ${p.unitCost.toStringAsFixed(2)}',
                    ),
                    trailing: Checkbox(
                      value: _selectedIds.contains(p.id),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedIds.add(p.id);
                          } else {
                            _selectedIds.remove(p.id);
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: _selectedIds.isEmpty
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  final result = await context.read<AppState>().importShopifyProducts();
                  final newC = result['newCount'] ?? 0;
                  final merged = result['mergedCount'] ?? 0;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '$newC new, $merged updated from Shopify',
                      ),
                    ),
                  );
                },
          child: const Text('Import Selected'),
        ),
      ],
    );
  }
}

// ─── Add Product Dialog ───────────────────────────────────────────────────────

class _AddProductDialog extends StatefulWidget {
  final List suppliers;
  final List manufacturers;
  final Product? existingProduct;
  final List<dynamic> warehouses;
  const _AddProductDialog({required this.suppliers, required this.manufacturers, required this.warehouses, this.existingProduct});

  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _skuCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _costCtrl = TextEditingController(text: '0.00');
  final _stockCtrl = TextEditingController(text: '0');
  final _leadTimeCtrl = TextEditingController(text: '0');
  String? _selectedSupplierId;
  String? _selectedManufacturerId;
  String? _selectedWarehouseId;

  bool get _isEdit => widget.existingProduct != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProduct;
    if (p != null) {
      _skuCtrl.text = p.sku;
      _nameCtrl.text = p.name;
      _categoryCtrl.text = p.category;
      _costCtrl.text = p.unitCost.toStringAsFixed(2);
      _stockCtrl.text = '${p.currentStock}';
      _leadTimeCtrl.text = '${p.leadTimeDays}';
      _selectedSupplierId = p.supplierId;
      _selectedManufacturerId = p.manufacturerId;
      _selectedWarehouseId = p.warehouseId;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Product' : 'Add New Product'),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _skuCtrl,
                        decoration: const InputDecoration(labelText: 'SKU'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'SKU is required' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Product Name',
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _categoryCtrl,
                        decoration: const InputDecoration(labelText: 'Category'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Category is required' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _costCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Unit Cost',
                          prefixText: 'EGP ',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final val = double.tryParse(v ?? '');
                          if (val == null || val < 0) return 'Enter a valid cost';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stockCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Current Stock',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final val = int.tryParse(v ?? '');
                          if (val == null || val < 0) return 'Enter a valid stock count';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'Supplier'),
                        // ignore: deprecated_member_use
                        value: _selectedSupplierId,
                        items: widget.suppliers
                            .map<DropdownMenuItem<String>>(
                              (s) => DropdownMenuItem<String>(
                                value: s.id as String,
                                child: Text(s.name as String),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedSupplierId = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _leadTimeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Lead Time (Days)',
                          helperText: '0 = use supplier default',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final val = int.tryParse(v ?? '');
                          if (val == null || val < 0) return 'Enter a valid number';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'Default Manufacturer'),
                        initialValue: _selectedManufacturerId,
                        items: widget.manufacturers
                            .map<DropdownMenuItem<String>>(
                              (m) => DropdownMenuItem<String>(
                                value: m.id as String,
                                child: Text(m.name as String),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedManufacturerId = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  decoration: const InputDecoration(
                    labelText: 'Warehouse',
                    helperText: 'Where this product is stored',
                  ),
                  initialValue: _selectedWarehouseId,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    ...widget.warehouses.map<DropdownMenuItem<String?>>(
                      (w) => DropdownMenuItem<String?>(
                        value: w.id as String,
                        child: Text('${w.name} — ${w.city}, ${w.country}'),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedWarehouseId = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: _save,
          child: Text(_isEdit ? 'Save Changes' : 'Save Product'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final product = Product(
      id: widget.existingProduct?.id ?? '',
      sku: _skuCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      category: _categoryCtrl.text.trim(),
      unitCost: double.tryParse(_costCtrl.text) ?? 0,
      currentStock: int.tryParse(_stockCtrl.text) ?? 0,
      supplierId: _selectedSupplierId,
      manufacturerId: _selectedManufacturerId,
      warehouseId: _selectedWarehouseId,
      leadTimeDays: int.tryParse(_leadTimeCtrl.text) ?? 0,
    );
    final appState = context.read<AppState>();
    try {
      if (_isEdit) {
        await appState.updateProduct(product);
      } else {
        await appState.addProduct(product);
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Product updated' : 'Product saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save product: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _skuCtrl.dispose();
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _costCtrl.dispose();
    _stockCtrl.dispose();
    _leadTimeCtrl.dispose();
    super.dispose();
  }
}
