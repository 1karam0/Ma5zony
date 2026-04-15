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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final suppliers = {for (final s in state.suppliers) s.id: s.name};
    final manufacturers = {for (final m in state.manufacturers) m.id: m.name};
    final bomMap = {for (final b in state.boms) b.finalProductId: b};

    final products = state.products.where((p) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q);
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
              child: Card(
                color: Colors.red.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.red.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber,
                          color: Colors.red, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$lowStockCount product(s) are running low on stock',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Create a purchase order to restock from your suppliers.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => context.go('/orders/create'),
                        icon: const Icon(Icons.shopping_cart),
                        label: const Text('Create Order'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
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

          if (products.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No products yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
                    SizedBox(height: 8),
                    Text('Add your first product to get started.', style: TextStyle(color: Colors.grey)),
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
              child: Theme(
                data: Theme.of(context).copyWith(cardColor: Colors.white),
                child: PaginatedDataTable(
                  header: Text(
                    '${products.length} Products',
                    style: AppTextStyles.h3,
                  ),
                  columns: const [
                    DataColumn(label: Text('SKU')),
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Category')),
                    DataColumn(label: Text('Unit Cost')),
                    DataColumn(label: Text('Stock')),
                    DataColumn(label: Text('Supplier')),
                    DataColumn(label: Text('Manufacturer')),
                    DataColumn(label: Text('BOM')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Actions')),
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
        .recommendations
        .where((r) => r.productId == p.id)
        .firstOrNull;

    final status = p.currentStock == 0
        ? 'Critical'
        : (recs != null ? 'Low' : 'OK');

    final mfrName = manufacturerMap[p.manufacturerId ?? ''] ?? '—';
    final bom = bomMap[p.id];
    final bomLabel = bom != null ? '${bom.materials.length} material(s)' : 'Not defined';

    return DataRow(
      cells: [
        DataCell(Text(p.sku)),
        DataCell(
          Text(
            p.name,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        DataCell(Text(p.category)),
        DataCell(Text('\$${p.unitCost.toStringAsFixed(2)}')),
        DataCell(Text('${p.currentStock} units')),
        DataCell(Text(supplierMap[p.supplierId ?? ''] ?? '—')),
        DataCell(Text(mfrName)),
        DataCell(
          bom != null
              ? InkWell(
                  onTap: () => _showBomPreview(context, p, bom),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.list_alt, size: 16, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(bomLabel,
                          style: const TextStyle(
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          )),
                    ],
                  ),
                )
              : InkWell(
                  onTap: () => _showBomPreview(context, p, null),
                  child: Text(bomLabel,
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
        ),
        DataCell(StatusChip(status)),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () {
                  final state = context.read<AppState>();
                  showDialog(
                    context: context,
                    builder: (_) => _AddProductDialog(
                      suppliers: state.suppliers,
                      manufacturers: state.manufacturers,
                      existingProduct: p,
                    ),
                  );
                },
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
                          SnackBar(content: Text('Failed to delete product: $e')),
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

  void _showBomPreview(BuildContext context, Product product, BillOfMaterials? bom) {
    final rmMap = {for (final m in rawMaterials) m.id: m};
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.list_alt, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('BOM — ${product.name}')),
          ],
        ),
        content: SizedBox(
          width: 550,
          child: bom == null || bom.materials.isEmpty
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 48, color: AppColors.textSecondary),
                    const SizedBox(height: 12),
                    const Text('No Bill of Materials defined for this product.'),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Define BOM'),
                      onPressed: () {
                        Navigator.pop(context);
                        GoRouter.of(context).go('/bom');
                      },
                    ),
                  ],
                )
              : SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Material')),
                      DataColumn(label: Text('Supplier')),
                      DataColumn(label: Text('Qty / Unit')),
                      DataColumn(label: Text('Unit Cost')),
                      DataColumn(label: Text('Line Cost')),
                    ],
                    rows: bom.materials.map((line) {
                      final rm = rmMap[line.rawMaterialId];
                      final unitCost = rm?.unitCost ?? 0.0;
                      final lineCost = line.quantityPerUnit * unitCost;
                      final supplierName =
                          rawMaterialSupplierMap[rm?.supplierId ?? ''] ?? '—';
                      return DataRow(cells: [
                        DataCell(Text(rm?.name ?? line.rawMaterialId)),
                        DataCell(Text(supplierName)),
                        DataCell(Text(
                            '${line.quantityPerUnit} ${rm?.unit ?? ''}')),
                        DataCell(
                            Text('\$${unitCost.toStringAsFixed(2)}')),
                        DataCell(
                            Text('\$${lineCost.toStringAsFixed(2)}')),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
        actions: [
          if (bom != null)
            TextButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text('Edit BOM'),
              onPressed: () {
                Navigator.pop(context);
                GoRouter.of(context).go('/bom');
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
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
                      '${p.sku} - \$${p.unitCost.toStringAsFixed(2)}',
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
                  await context.read<AppState>().importShopifyProducts();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '${_selectedIds.length} product(s) imported from Shopify',
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
  const _AddProductDialog({required this.suppliers, required this.manufacturers, this.existingProduct});

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
  String? _selectedSupplierId;
  String? _selectedManufacturerId;

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
      _selectedSupplierId = p.supplierId;
      _selectedManufacturerId = p.manufacturerId;
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
                          prefixText: '\$',
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
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Default Manufacturer'),
                  value: _selectedManufacturerId,
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
          onPressed: () async {
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
            );
            final appState = context.read<AppState>();
            final messenger = ScaffoldMessenger.of(context);
            final nav = Navigator.of(context);
            try {
              if (_isEdit) {
                await appState.updateProduct(product);
              } else {
                await appState.addProduct(product);
              }
              nav.pop();
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(content: Text('Failed to save product: $e'), backgroundColor: Colors.red),
              );
            }
          },
          child: Text(_isEdit ? 'Save Changes' : 'Save Product'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _skuCtrl.dispose();
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _costCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }
}
