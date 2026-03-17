// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/product.dart';
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
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Actions')),
                  ],
                  source: _ProductDataSource(
                    products: products,
                    supplierMap: suppliers,
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
      builder: (ctx) => _AddProductDialog(suppliers: state.suppliers),
    );
  }
}

// ─── DataTableSource ──────────────────────────────────────────────────────────

class _ProductDataSource extends DataTableSource {
  final List<Product> products;
  final Map<String, String> supplierMap;
  final BuildContext context;

  _ProductDataSource({
    required this.products,
    required this.supplierMap,
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
        DataCell(StatusChip(status)),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () {},
                tooltip: 'Edit',
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete,
                  size: 20,
                  color: AppColors.error,
                ),
                onPressed: () {},
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

// ─── Import Dialog ────────────────────────────────────────────────────────────

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final Set<String> _selectedIds = {};

  final _mockShopifyProducts = [
    {'id': 'sp_101', 'sku': 'SH-NEW-01', 'name': 'Summer Hat', 'price': 25.0},
    {'id': 'sp_102', 'sku': 'SH-NEW-02', 'name': 'Beach Towel', 'price': 40.0},
    {'id': 'sp_103', 'sku': 'SH-NEW-03', 'name': 'Sunglasses', 'price': 150.0},
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import from Shopify'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  value: _selectedIds.length == _mockShopifyProducts.length,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedIds.addAll(
                          _mockShopifyProducts.map((p) => p['id'] as String),
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
                itemCount: _mockShopifyProducts.length,
                itemBuilder: (context, i) {
                  final p = _mockShopifyProducts[i];
                  final id = p['id'] as String;
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      color: Colors.grey[200],
                      child: const Icon(Icons.image),
                    ),
                    title: Text(p['name'] as String),
                    subtitle: Text('${p['sku']} - \$${p['price']}'),
                    trailing: Checkbox(
                      value: _selectedIds.contains(id),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedIds.add(id);
                          } else {
                            _selectedIds.remove(id);
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
  const _AddProductDialog({required this.suppliers});

  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  final _skuCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _costCtrl = TextEditingController(text: '0.00');
  final _stockCtrl = TextEditingController(text: '0');
  String? _selectedSupplierId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Product'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _skuCtrl,
                      decoration: const InputDecoration(labelText: 'SKU'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Product Name',
                      ),
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
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Supplier'),
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
            ],
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
          onPressed: () {
            // In a real app, this would persist via the repository.
            // For now we show the dialog and close it.
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Product "${_nameCtrl.text.isEmpty ? 'New Product' : _nameCtrl.text}" added',
                ),
              ),
            );
          },
          child: const Text('Save Product'),
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
