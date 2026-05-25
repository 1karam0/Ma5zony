import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';
import 'package:ma5zony/widgets/zoho_patterns.dart';
import 'package:ma5zony/features/onboarding/tour_targets.dart';

/// Opens the product Add/Edit dialog pre-filled for [product]. The dialog
/// Quick inline dialog to set / edit just the supplier price (unit cost) of
/// a *purchased* product. Saves without touching any other field.
///
/// **Don't call this for manufactured products** — their cost is rolled up
/// from BOM materials + production fee, never typed manually. Use
/// [showProductCostFixDialog] which dispatches to the correct flow.
Future<void> showQuickCostDialog(
    BuildContext context, Product product) async {
  final ctrl = TextEditingController(
      text: product.unitCost > 0
          ? product.unitCost.toStringAsFixed(2)
          : '');
  final formKey = GlobalKey<FormState>();
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Set Supplier Price'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How much does your supplier charge you per unit of '
              '"${product.name}"?',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Supplier price per unit (EGP)',
                prefixText: 'EGP ',
                helperText: 'Cost basis — used in inventory cost, COGS & margin.',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter a price';
                if (double.tryParse(v.trim()) == null) {
                  return 'Enter a valid number';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            if (!formKey.currentState!.validate()) return;
            final newCost = double.parse(ctrl.text.trim());
            final updated = Product(
              id: product.id,
              sku: product.sku,
              name: product.name,
              category: product.category,
              unitCost: newCost,
              currentStock: product.currentStock,
              supplierId: product.supplierId,
              manufacturerId: product.manufacturerId,
              warehouseId: product.warehouseId,
              isActive: product.isActive,
              leadTimeDays: product.leadTimeDays,
              averageDailySales: product.averageDailySales,
              minimumStock: product.minimumStock,
              shopifyVariantId: product.shopifyVariantId,
              shopifyProductId: product.shopifyProductId,
              sellingPrice: product.sellingPrice,
              productionFee: product.productionFee,
              shopifyUnitCost: product.shopifyUnitCost,
              isBundle: product.isBundle,
              bundleComponents: product.bundleComponents,
              sourcingOptions: product.sourcingOptions,
              stockByWarehouse: product.stockByWarehouse,
            );
            if (ctx.mounted) {
              await ctx.read<AppState>().updateProduct(updated);
              Navigator.pop(ctx);
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  ctrl.dispose();
}

/// Smart entry point used by the products table "needs cost" cell. Routes
/// the user to the correct flow based on whether the product is purchased
/// or manufactured:
///
///   • **Purchased** (no manufacturerId) → opens the quick supplier-price
///     dialog above. The user just types what the supplier charges.
///   • **Manufactured** (manufacturerId set) → opens the full product edit
///     dialog so the user can build/edit the BOM. Cost is auto-derived from
///     materials + production fee — typing a manual figure would silently
///     contradict the BOM rollup and break downstream KPIs.
Future<void> showProductCostFixDialog(
    BuildContext context, Product product) async {
  final isManufactured =
      product.manufacturerId != null && product.manufacturerId!.isNotEmpty;
  if (isManufactured) {
    await showProductEditDialog(context, product);
  } else {
    await showQuickCostDialog(context, product);
  }
}

/// Opens the full product edit form for an existing product. The full form
/// includes Supplier and Manufacturer pickers, lead time, unit cost, etc.
/// Used by other screens (e.g. the Forecasts readiness gate) to jump straight
/// to the form where supplier / manufacturer are linked to a product.
Future<void> showProductEditDialog(BuildContext context, Product product,
    {String? hintSku}) async {
  final state = context.read<AppState>();
  await showDialog(
    context: context,
    builder: (_) => _AddProductDialog(
      suppliers: state.suppliers,
      manufacturers: state.manufacturers,
      warehouses: state.warehouses,
      rawMaterials: state.rawMaterials,
      existingProduct: product,
      existingBom: state.boms.where((b) => b.finalProductId == product.id).firstOrNull,
      hintSku: hintSku,
    ),
  );
}

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _search = '';
  String _statusFilter = 'All'; // All | OK | Low | Critical | Needs Setup

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final suppliers = {for (final s in state.suppliers) s.id: s.name};
    final manufacturers = {for (final m in state.manufacturers) m.id: m.name};
    final bomMap = {for (final b in state.boms) b.finalProductId: b};

    final recs = {for (final r in state.recommendations) r.productId: r};

    // Build a set of product IDs that fail the setup-health check. A product
    // is "needs setup" if any of: zero effective unit cost, no supplier (and
    // not manufactured), or manufactured-but-no-BOM.
    final missingCostIds = {for (final p in state.productsMissingCost) p.id};
    final missingSupplierIds = {
      for (final p in state.productsMissingSupplier) p.id
    };
    final missingBomIds = {
      for (final p in state.manufacturedProductsMissingBom) p.id
    };
    final needsSetupIds = {...missingCostIds, ...missingSupplierIds, ...missingBomIds};

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
      if (_statusFilter == 'Needs Setup') {
        if (!needsSetupIds.contains(p.id)) return false;
      } else if (_statusFilter != 'All') {
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

          // Product setup-health banner. Shown when any active product is
          // missing the data the rest of the system depends on (cost,
          // supplier, or BOM for manufactured items). Without this, every
          // KPI silently lies — so we make the fix one click away.
          Builder(builder: (context) {
            final missingCost = state.productsMissingCost.length;
            final missingSupplier = state.productsMissingSupplier.length;
            final missingBom = state.manufacturedProductsMissingBom.length;
            final totalGaps = missingCost + missingSupplier + missingBom;
            if (totalGaps == 0 || state.products.isEmpty) {
              return const SizedBox.shrink();
            }
            final parts = <String>[
              if (missingCost > 0)
                '$missingCost missing unit cost',
              if (missingSupplier > 0)
                '$missingSupplier missing supplier',
              if (missingBom > 0)
                '$missingBom missing BOM',
            ];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: AlertBanner(
                severity: AlertSeverity.warning,
                title: 'Finish product setup to trust your KPIs',
                message:
                    '${parts.join(' · ')}. Inventory cost, COGS and margin are '
                    'calculated from these fields — leave them blank and the '
                    'dashboard numbers will be wrong.',
                action: TextButton(
                  onPressed: () =>
                      setState(() => _statusFilter = 'Needs Setup'),
                  child: const Text('Show items'),
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
              KeyedSubtree(
                key: TourTargets.instance.keyFor('page:products.import'),
                child: OutlinedButton.icon(
                  onPressed: () => _showImportDialog(context),
                  icon: const Icon(Icons.cloud_download),
                  label: const Text('Import from Shopify'),
                ),
              ),
              const SizedBox(width: 16),
              KeyedSubtree(
                key: TourTargets.instance.keyFor('page:products.add'),
                child: ElevatedButton.icon(
                  onPressed: () => _showAddProductDialog(context, state),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Product'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          // Status filter chips
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              children: ['All', 'Needs Setup', 'OK', 'Low', 'Critical'].map((filter) {
                final isActive = _statusFilter == filter;
                final chipColor = filter == 'Critical'
                    ? AppColors.error
                    : filter == 'Low'
                        ? AppColors.warning
                        : filter == 'OK'
                            ? AppColors.success
                            : filter == 'Needs Setup'
                                ? AppColors.warning
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
                  DataColumn(label: Text('SELLING PRICE', style: AppTextStyles.tableHeader), numeric: true),
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
        rawMaterials: state.rawMaterials,
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
        // Unit Cost — what it COSTS you to get/make this product.
        //
        // Purchased products → manual `unitCost` field (what the supplier
        // charges per unit).
        // Manufactured products → ROLLED UP from BOM materials + production
        // fee via AppState.effectiveUnitCost. Never typed directly; doing so
        // would silently disagree with the BOM and break every KPI.
        //
        // Legacy: a few products from before sellingPrice existed have their
        // Shopify selling price stored in unitCost. Detect that and prompt
        // the user to set a real cost.
        DataCell(
          () {
            final appState = context.read<AppState>();
            final effective = appState.effectiveUnitCost(p);
            final isManufactured =
                p.manufacturerId != null && p.manufacturerId!.isNotEmpty;
            final hasBom = appState.boms
                .any((b) => b.finalProductId == p.id && b.isActive);
            final sp = p.sellingPrice ?? 0;
            final isLegacy = !isManufactured &&
                p.unitCost > 0 &&
                (sp == 0 || (sp - p.unitCost).abs() < 0.01);

            // Needs-fix states. Manufactured = no BOM (or BOM materials cost
            // out to 0). Purchased = unitCost 0 OR legacy.
            if (effective <= 0 || isLegacy) {
              final label = isManufactured
                  ? (hasBom ? 'Fix BOM' : 'Set up BOM')
                  : 'Set supplier price';
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isManufactured
                        ? Icons.account_tree_outlined
                        : Icons.warning_amber_rounded,
                    size: 14,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(label,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.warning)),
                ],
              );
            }
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'EGP ${effective.toStringAsFixed(2)}',
                  style: AppTextStyles.tableNum,
                  textAlign: TextAlign.right,
                ),
                const SizedBox(width: 4),
                Icon(
                  isManufactured
                      ? Icons.account_tree_outlined
                      : Icons.edit_outlined,
                  size: 12,
                  color: AppColors.textSubdued,
                ),
              ],
            );
          }(),
          onTap: () => showProductCostFixDialog(context, p),
        ),
        // Selling Price — what the customer pays.
        // For legacy products where sellingPrice was never stored separately,
        // fall back to displaying unitCost (which IS the selling price).
        DataCell(
          () {
            final sp = p.sellingPrice ?? 0;
            final displayPrice = sp > 0 ? sp : p.unitCost;
            if (displayPrice == 0) {
              return Text('—',
                  style: AppTextStyles.tableNum
                      .copyWith(color: AppColors.textSubdued),
                  textAlign: TextAlign.right);
            }
            return Text(
              'EGP ${displayPrice.toStringAsFixed(2)}',
              style: AppTextStyles.tableNum,
              textAlign: TextAlign.right,
            );
          }(),
        ),
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
                      rawMaterials: st.rawMaterials,
                      existingProduct: p,
                      existingBom: st.boms
                          .where((b) => b.finalProductId == p.id)
                          .firstOrNull,
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
    final isManufactured = product.manufacturerId != null &&
        product.manufacturerId!.isNotEmpty;
    final isFromSupplier = !isManufactured &&
        product.supplierId != null &&
        product.supplierId!.isNotEmpty;

    final hasWarehouse =
        product.warehouseId != null && product.warehouseId!.isNotEmpty;

    // ── Manufactured path: needs BOM + at least one material has a supplier ──
    if (isManufactured) {
      final bom = bomMap[product.id];
      final hasBom = bom != null;
      final hasSupplier = bom != null &&
          bom.materials.any((m) => rawMaterials.any(
              (r) =>
                  r.id == m.rawMaterialId &&
                  r.supplierId != null &&
                  (r.supplierId as String).isNotEmpty));

      String? fixPath;
      String? fixLabel;
      if (!hasBom) {
        fixPath = '/bom';
        fixLabel = 'Set up BOM';
      } else if (!hasSupplier) {
        fixPath = '/raw-materials';
        fixLabel = 'Add Supplier to material';
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
              _FixLink(label: fixLabel!, path: fixPath, context: context),
          ],
        ),
      );
    }

    // ── From-supplier path: no BOM needed — just supplier + warehouse ────────
    if (isFromSupplier) {
      String? fixPath;
      String? fixLabel;
      if (!hasWarehouse) {
        fixPath = '/warehouses';
        fixLabel = 'Assign Warehouse';
      }
      final allGood = hasWarehouse;

      return SizedBox(
        width: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                _ChainBadge(label: 'Supplier', ok: true),
                const SizedBox(width: 4),
                _ChainBadge(label: 'Warehouse', ok: hasWarehouse),
              ],
            ),
            if (!allGood && fixPath != null)
              _FixLink(label: fixLabel!, path: fixPath, context: context),
          ],
        ),
      );
    }

    // ── Sourcing type not yet set ─────────────────────────────────────────────
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              _ChainBadge(label: 'Supplier', ok: false),
              const SizedBox(width: 4),
              _ChainBadge(label: 'Warehouse', ok: hasWarehouse),
            ],
          ),
          _FixLink(
            label: 'Set sourcing type',
            path: null,
            context: context,
            onTap: () => showProductEditDialog(context, product),
          ),
        ],
      ),
    );
  }
}

class _FixLink extends StatelessWidget {
  final String label;
  final String? path;
  final BuildContext context;
  final VoidCallback? onTap;
  const _FixLink(
      {required this.label,
      required this.path,
      required this.context,
      this.onTap});

  @override
  Widget build(BuildContext ctx) {
    return InkWell(
      onTap: onTap ?? (path != null ? () => context.go(path!) : null),
      child: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
            const Icon(Icons.arrow_forward_ios,
                size: 8, color: AppColors.primary),
          ],
        ),
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
  final List<dynamic> rawMaterials;
  final BillOfMaterials? existingBom;
  /// When set, shows a Shopify SKU suggestion banner inside the dialog.
  final String? hintSku;
  const _AddProductDialog({
    required this.suppliers,
    required this.manufacturers,
    required this.warehouses,
    required this.rawMaterials,
    this.existingProduct,
    this.existingBom,
    this.hintSku,
  });

  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

enum _ProductSourceType { purchased, manufactured }

/// State for one alternative (non-default) sourcing option row.
/// Always "purchase" kind — manufacture alternatives share the product BOM.
class _AltSourceRow {
  String? supplierId;
  final TextEditingController costCtrl;
  final TextEditingController leadTimeCtrl;
  final TextEditingController moqCtrl;
  _AltSourceRow({this.supplierId, double cost = 0, int leadTime = 0, int? moq})
      : costCtrl =
            TextEditingController(text: cost > 0 ? cost.toStringAsFixed(2) : ''),
        leadTimeCtrl =
            TextEditingController(text: leadTime > 0 ? '$leadTime' : ''),
        moqCtrl = TextEditingController(text: moq != null ? '$moq' : '');
  void dispose() {
    costCtrl.dispose();
    leadTimeCtrl.dispose();
    moqCtrl.dispose();
  }
}

class _BomRowState {
  /// Holds either a raw-material id or a sub-product id depending on [kind].
  String? rawMaterialId;
  final TextEditingController qtyCtrl;
  final TextEditingController yieldCtrl;
  String uom;
  BomComponentKind kind;
  _BomRowState({
    this.rawMaterialId,
    double qty = 1,
    this.uom = 'pcs',
    this.kind = BomComponentKind.rawMaterial,
    double? yieldPercent,
  })  : qtyCtrl = TextEditingController(
            text: qty == qty.truncate()
                ? qty.toStringAsFixed(0)
                : qty.toString()),
        yieldCtrl = TextEditingController(
            text: (yieldPercent == null || yieldPercent == 100)
                ? ''
                : yieldPercent.toStringAsFixed(
                    yieldPercent == yieldPercent.truncate() ? 0 : 1));
  void dispose() {
    qtyCtrl.dispose();
    yieldCtrl.dispose();
  }

  /// Effective qty consumed once yield loss is applied. Mirrors
  /// [BomMaterial.effectiveQuantityPerUnit] so the cost preview matches the
  /// final persisted value.
  double get effectiveQty {
    final base = double.tryParse(qtyCtrl.text) ?? 0;
    final y = double.tryParse(yieldCtrl.text);
    if (y == null || y >= 100 || y <= 0) return base;
    return base / (y / 100.0);
  }
}

class _AddProductDialogState extends State<_AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _skuCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _costCtrl = TextEditingController(text: '0.00');
  final _sellingPriceCtrl = TextEditingController(text: '0.00');
  final _productionFeeCtrl = TextEditingController(text: '0.00');
  final _stockCtrl = TextEditingController(text: '0');
  final _leadTimeCtrl = TextEditingController(text: '0');
  String? _selectedSupplierId;
  String? _selectedManufacturerId;
  String? _selectedWarehouseId;
  _ProductSourceType _sourceType = _ProductSourceType.purchased;
  final List<_BomRowState> _bomRows = [];
  final List<_AltSourceRow> _altSourcingOptions = [];
  /// Controllers for per-warehouse stock counts. Keyed by [Warehouse.id].
  /// Populated in initState from the existing product; empty = not yet
  /// populated (single-location fallback).
  final Map<String, TextEditingController> _whStockCtrls = {};

  bool get _isEdit => widget.existingProduct != null;

  /// Sum of (effective qty × component unit cost) across all BOM rows.
  /// "Effective qty" applies yield loss so a 15% scrap recipe consumes more
  /// input than the typed amount. Sub-assembly rows pull cost from
  /// AppState.effectiveUnitCost so nested BOMs roll up correctly.
  double get _computedMaterialCost {
    double total = 0;
    final appState = context.read<AppState>();
    for (final row in _bomRows) {
      if (row.rawMaterialId == null || row.rawMaterialId!.isEmpty) continue;
      final qty = row.effectiveQty;
      if (qty <= 0) continue;
      if (row.kind == BomComponentKind.product) {
        final sub = appState.products
            .where((p) => p.id == row.rawMaterialId)
            .firstOrNull;
        if (sub != null) total += qty * appState.effectiveUnitCost(sub);
      } else {
        final rm = widget.rawMaterials
            .where((m) => m.id == row.rawMaterialId)
            .firstOrNull;
        if (rm != null) total += qty * (rm.unitCost as double);
      }
    }
    return total;
  }

  double get _computedTotalCost =>
      _computedMaterialCost + (double.tryParse(_productionFeeCtrl.text) ?? 0);

  @override
  void initState() {
    super.initState();
    final p = widget.existingProduct;
    if (p != null) {
      _skuCtrl.text = p.sku;
      _nameCtrl.text = p.name;
      _categoryCtrl.text = p.category;
      _costCtrl.text = p.unitCost.toStringAsFixed(2);
      _sellingPriceCtrl.text =
          (p.sellingPrice ?? 0).toStringAsFixed(2);
      _productionFeeCtrl.text =
          (p.productionFee ?? 0).toStringAsFixed(2);
      _stockCtrl.text = '${p.currentStock}';
      _leadTimeCtrl.text = '${p.leadTimeDays}';
      // Validate IDs against the passed lists so no DropdownButton assertion
      // fires if the lists haven't loaded yet or IDs became stale.
      _selectedSupplierId = widget.suppliers.any((s) => s.id == p.supplierId)
          ? p.supplierId
          : null;
      _selectedManufacturerId =
          widget.manufacturers.any((m) => m.id == p.manufacturerId)
              ? p.manufacturerId
              : null;
      _selectedWarehouseId =
          widget.warehouses.any((w) => w.id == p.warehouseId)
              ? p.warehouseId
              : null;
      // Infer source: if a manufacturer is set on the existing product,
      // treat it as manufactured; otherwise purchased.
      _sourceType = (_selectedManufacturerId != null &&
              _selectedManufacturerId!.isNotEmpty)
          ? _ProductSourceType.manufactured
          : _ProductSourceType.purchased;
    }
    // Seed BOM rows from the existing recipe, if any.
    final bom = widget.existingBom;
    if (bom != null) {
      for (final m in bom.materials) {
        _bomRows.add(_BomRowState(
          rawMaterialId: m.refId,
          qty: m.quantityPerUnit,
          uom: m.unitOfMeasure,
          kind: m.kind,
          yieldPercent: m.yieldPercent,
        ));
      }
    }
    // Seed alternative sourcing options (non-default entries only).
    if (p != null) {
      for (final opt in p.sourcingOptions.where((o) => !o.isDefault)) {
        final supplier = widget.suppliers.any((s) => s.id == opt.supplierId)
            ? opt.supplierId
            : null;
        _altSourcingOptions.add(_AltSourceRow(
          supplierId: supplier,
          cost: opt.unitCost,
          leadTime: opt.leadTimeDays,
          moq: opt.moq,
        ));
      }
    }
    // Seed per-warehouse stock controllers from the existing product. One
    // controller is created for EVERY warehouse in the passed list so the
    // table always shows all locations (even if stock is 0 there).
    // For Shopify-imported products the per-warehouse breakdown may be empty
    // even though currentStock > 0 — in that case, seed the first warehouse
    // (or the one already assigned) with the flat total so the user doesn't
    // have to re-enter the existing stock manually.
    final profile = context.read<AppState>().settings.businessProfile;
    if (profile != null && profile.isMultiLocation) {
      final hasBreakdown = p != null && p.stockByWarehouse.isNotEmpty;
      final fallbackWarehouseId = p?.warehouseId ?? widget.warehouses.firstOrNull?.id;
      for (final w in widget.warehouses) {
        int qty = p?.stockAtWarehouse(w.id) ?? 0;
        if (!hasBreakdown &&
            p != null &&
            p.currentStock > 0 &&
            w.id == fallbackWarehouseId) {
          qty = p.currentStock;
        }
        _whStockCtrls[w.id] = TextEditingController(text: '$qty');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                Text(_isEdit ? 'Edit Product' : 'New Product',
                    style: AppTextStyles.h3),
                const SizedBox(height: 2),
                Text(
                  _isEdit
                      ? 'Update product details and supply chain settings.'
                      : 'Add a new SKU to your catalog. Required fields are in red.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.textSecondary,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Shopify SKU hint banner ───────────────────────────────
                if (widget.hintSku != null &&
                    _skuCtrl.text.trim() != widget.hintSku) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.storefront_outlined,
                            size: 16, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Shopify didn\'t find a match for this product. '
                            'Suggested SKU from Shopify: ${widget.hintSku}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () =>
                              setState(() => _skuCtrl.text = widget.hintSku!),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.warning,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: const Size(0, 28),
                            textStyle: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          child: const Text('Use this SKU'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // ── Section 1: Basic Information ─────────────────────────
                ZohoFormSection(
                  title: 'Basic Information',
                  subtitle: 'Identify the product within your catalog.',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _skuCtrl,
                            decoration: const InputDecoration(labelText: 'SKU *'),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'SKU is required'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Product Name *',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Name is required'
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _categoryCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Category *',
                        hintText: 'e.g. Apparel, Electronics, Raw Goods',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Category is required'
                          : null,
                    ),
                  ],
                ),

                // ── Section 2: Pricing & Inventory ───────────────────────
                ZohoFormSection(
                  title: 'Pricing & Inventory',
                  subtitle: _sourceType == _ProductSourceType.manufactured
                      ? 'Cost is calculated from raw materials + production fee. Set the selling price you charge customers.'
                      : 'Enter the cost you pay per unit (drives EOQ & spend forecasts) and the price you sell it for.',
                  children: [
                    // ── Row 1: Cost + Stock ──────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cost field (editable for purchased; read-only computed for manufactured)
                        Expanded(
                          child: _sourceType == _ProductSourceType.manufactured
                              ? StatefulBuilder(
                                  builder: (ctx, _) => InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: 'Unit Cost (auto-calculated)',
                                      prefixText: 'EGP ',
                                      helperText:
                                          'Materials + production fee',
                                      filled: true,
                                      fillColor: AppColors.background,
                                    ),
                                    child: Text(
                                      _computedTotalCost.toStringAsFixed(2),
                                      style: AppTextStyles.body,
                                    ),
                                  ),
                                )
                              : TextFormField(
                                  controller: _costCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Unit Cost *',
                                    prefixText: 'EGP ',
                                    helperText:
                                        'Price you pay per unit to supplier',
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (v) {
                                    final val = double.tryParse(v ?? '');
                                    if (val == null || val < 0) {
                                      return 'Enter a valid cost';
                                    }
                                    return null;
                                  },
                                ),
                        ),
                        const SizedBox(width: 16),
                        // Selling price (always editable; pre-filled from Shopify if connected)
                        Expanded(
                          child: TextFormField(
                            controller: _sellingPriceCtrl,
                            decoration: InputDecoration(
                              labelText: 'Selling Price',
                              prefixText: 'EGP ',
                              helperText: widget.existingProduct?.shopifyVariantId != null
                                  ? 'Synced from Shopify — edit to override'
                                  : 'Price charged to customers',
                              suffixIcon: widget.existingProduct?.shopifyVariantId != null
                                  ? const Tooltip(
                                      message: 'Linked to Shopify',
                                      child: Icon(Icons.store_outlined,
                                          size: 18),
                                    )
                                  : null,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            validator: (v) {
                              if (v == null || v.isEmpty) return null;
                              final val = double.tryParse(v);
                              if (val == null || val < 0) {
                                return 'Enter a valid price';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    // ── Row 2: Production Fee (manufactured only) + Stock ─
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_sourceType == _ProductSourceType.manufactured) ...[
                          Expanded(
                            child: TextFormField(
                              controller: _productionFeeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Production Fee per Unit',
                                prefixText: 'EGP ',
                                helperText:
                                    'Manufacturer charge on top of materials',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => setState(() {}),
                              validator: (v) {
                                if (v == null || v.isEmpty) return null;
                                final val = double.tryParse(v);
                                if (val == null || val < 0) {
                                  return 'Enter a valid fee';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                        ],
                        Expanded(
                          child: _whStockCtrls.isNotEmpty
                              ? _buildStockByWarehouseField()
                              : TextFormField(
                                  controller: _stockCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Current Stock *',
                                    suffixText: 'units',
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (v) {
                                    final val = int.tryParse(v ?? '');
                                    if (val == null || val < 0) {
                                      return 'Enter a valid stock count';
                                    }
                                    return null;
                                  },
                                ),
                        ),
                      ],
                    ),
                    // ── Margin hint (when both cost and selling price filled) ──
                    if (_sellingPriceCtrl.text.isNotEmpty &&
                        (double.tryParse(_sellingPriceCtrl.text) ?? 0) > 0)
                      Builder(builder: (ctx) {
                        final sp =
                            double.tryParse(_sellingPriceCtrl.text) ?? 0;
                        final cost = _sourceType ==
                                _ProductSourceType.manufactured
                            ? _computedTotalCost
                            : (double.tryParse(_costCtrl.text) ?? 0);
                        if (sp <= 0) return const SizedBox.shrink();
                        final margin = sp > 0 ? ((sp - cost) / sp * 100) : 0.0;
                        final marginColor = margin >= 30
                            ? AppColors.success
                            : margin >= 10
                                ? AppColors.warning
                                : AppColors.error;
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              Icon(Icons.bar_chart_rounded,
                                  size: 16, color: marginColor),
                              const SizedBox(width: 6),
                              Text(
                                'Gross margin: ${margin.toStringAsFixed(1)}%'
                                '  (Cost EGP ${cost.toStringAsFixed(2)} → Sell EGP ${sp.toStringAsFixed(2)})',
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: marginColor),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),

                // ── Section 3: Supply Chain ──────────────────────────────
                ZohoFormSection(
                  title: 'Supply Chain',
                  subtitle:
                      'How does this product reach your warehouse?',
                  collapsible: true,
                  initiallyExpanded: true,
                  children: [
                    TypeSelectorGroup<_ProductSourceType>(
                      value: _sourceType,
                      onChanged: (v) => setState(() {
                        _sourceType = v;
                        // Enforce mutual exclusion as the user toggles.
                        if (v == _ProductSourceType.purchased) {
                          _selectedManufacturerId = null;
                        } else {
                          _selectedSupplierId = null;
                        }
                      }),
                      options: const [
                        TypeOption(
                          value: _ProductSourceType.purchased,
                          label: 'Purchased from supplier',
                          icon: Icons.local_shipping_outlined,
                        ),
                        TypeOption(
                          value: _ProductSourceType.manufactured,
                          label: 'Manufactured for us',
                          icon: Icons.precision_manufacturing_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_sourceType == _ProductSourceType.purchased)
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Supplier *',
                          helperText:
                              'Replenishment approvals will create a purchase order for this supplier.',
                        ),
                        initialValue: _selectedSupplierId,
                        items: widget.suppliers
                            .map<DropdownMenuItem<String>>(
                              (s) => DropdownMenuItem<String>(
                                value: s.id as String,
                                child: Text(s.name as String),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedSupplierId = v),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Pick a supplier for purchased products'
                            : null,
                      )
                    else
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Manufacturer *',
                          helperText:
                              'Replenishment approvals will create a production order with this manufacturer.',
                        ),
                        initialValue: _selectedManufacturerId,
                        items: widget.manufacturers
                            .map<DropdownMenuItem<String>>(
                              (m) => DropdownMenuItem<String>(
                                value: m.id as String,
                                child: Text(m.name as String),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedManufacturerId = v),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Pick a manufacturer for manufactured products'
                            : null,
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _leadTimeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Lead Time Override (Days)',
                              hintText: 'e.g. 14',
                              helperText:
                                  'How long restocking takes for this product specifically. Leave 0 to inherit from the supplier.',
                              helperMaxLines: 2,
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              final val = int.tryParse(v ?? '');
                              if (val == null || val < 0) {
                                return 'Enter a valid number';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
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
                              ...widget.warehouses
                                  .map<DropdownMenuItem<String?>>(
                                (w) => DropdownMenuItem<String?>(
                                  value: w.id as String,
                                  child: Text(
                                      '${w.name} — ${w.city}, ${w.country}'),
                                ),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _selectedWarehouseId = v),
                          ),
                        ),
                      ],
                    ),
                    // ── Alternative Sources (backup suppliers) ─────────
                    // Only purchase-type alternatives make sense here since
                    // manufactured alternatives share the same BOM.
                    if (_sourceType == _ProductSourceType.purchased) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Alternative Sources',
                                  style: AppTextStyles.bodySmall.copyWith(
                                      fontWeight: FontWeight.w600)),
                              Text(
                                'Backup suppliers used when the primary is unavailable.',
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: widget.suppliers.isEmpty
                                ? null
                                : () => setState(() =>
                                    _altSourcingOptions.add(_AltSourceRow())),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                      if (_altSourcingOptions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No alternatives added.',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        )
                      else
                        ..._altSourcingOptions.asMap().entries.map((e) {
                          final i = e.key;
                          final alt = e.value;
                          return Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<String>(
                                    decoration: const InputDecoration(
                                        labelText: 'Alt. Supplier'),
                                    initialValue: alt.supplierId,
                                    items: widget.suppliers
                                        .map<DropdownMenuItem<String>>(
                                          (s) => DropdownMenuItem<String>(
                                            value: s.id as String,
                                            child: Text(s.name as String),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setState(
                                        () => alt.supplierId = v),
                                    validator: (v) =>
                                        (v == null || v.isEmpty)
                                            ? 'Pick a supplier'
                                            : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: alt.costCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Unit Cost',
                                      prefixText: 'EGP ',
                                    ),
                                    keyboardType: const TextInputType
                                        .numberWithOptions(decimal: true),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return null;
                                      }
                                      final n = double.tryParse(v.trim());
                                      if (n == null || n < 0) {
                                        return 'Invalid cost';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: alt.leadTimeCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Lead Time',
                                      suffixText: 'd',
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return null;
                                      }
                                      final n = int.tryParse(v.trim());
                                      if (n == null || n < 0) {
                                        return 'Invalid';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: alt.moqCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'MOQ',
                                      suffixText: 'units',
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return null;
                                      }
                                      final n = int.tryParse(v.trim());
                                      if (n == null || n < 0) {
                                        return 'Invalid';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove',
                                  icon: const Icon(
                                      Icons.remove_circle_outline,
                                      color: AppColors.error),
                                  onPressed: () => setState(() {
                                    _altSourcingOptions[i].dispose();
                                    _altSourcingOptions.removeAt(i);
                                  }),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ],
                ),

                // ── Section 4: Raw Materials Used (Manufactured only) ────
                if (_sourceType == _ProductSourceType.manufactured)
                  ZohoFormSection(
                    title: 'Raw Materials Used',
                    subtitle:
                        'How much of each raw material is consumed to build one unit of this product. Drives raw-material orders when production is scheduled.',
                    children: [
                      if (_bomRows.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            widget.rawMaterials.isEmpty
                                ? 'No raw materials defined yet. Add raw materials first, then come back to link them.'
                                : 'No materials added yet. Click "Add Material" to specify how much of each is used per unit.',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        )
                      else
                        ..._bomRows.asMap().entries.map((e) {
                          final i = e.key;
                          final row = e.value;
                          // Available sub-assemblies: manufactured products
                          // OTHER than the one being edited (prevents an
                          // obvious self-reference; the cycle guard in
                          // effectiveUnitCost catches transitive loops).
                          final subAssemblies = context
                              .read<AppState>()
                              .products
                              .where((p) =>
                                  p.manufacturerId != null &&
                                  p.manufacturerId!.isNotEmpty &&
                                  p.id != widget.existingProduct?.id)
                              .toList();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Kind toggle: raw material vs sub-assembly
                                // (Phase 2.3 nesting).
                                Row(
                                  children: [
                                    ChoiceChip(
                                      label: const Text('Raw material'),
                                      selected: row.kind ==
                                          BomComponentKind.rawMaterial,
                                      onSelected: (s) {
                                        if (!s) return;
                                        setState(() {
                                          row.kind =
                                              BomComponentKind.rawMaterial;
                                          row.rawMaterialId = null;
                                        });
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    ChoiceChip(
                                      label: const Text('Sub-assembly'),
                                      selected: row.kind ==
                                          BomComponentKind.product,
                                      onSelected: subAssemblies.isEmpty
                                          ? null
                                          : (s) {
                                              if (!s) return;
                                              setState(() {
                                                row.kind =
                                                    BomComponentKind.product;
                                                row.rawMaterialId = null;
                                                row.uom = 'pcs';
                                              });
                                            },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: row.kind ==
                                              BomComponentKind.rawMaterial
                                          ? DropdownButtonFormField<String>(
                                              decoration: const InputDecoration(
                                                labelText: 'Raw Material *',
                                              ),
                                              initialValue: row.rawMaterialId,
                                              items: widget.rawMaterials
                                                  .map<DropdownMenuItem<String>>(
                                                    (rm) =>
                                                        DropdownMenuItem<String>(
                                                      value: rm.id as String,
                                                      child: Text(
                                                        '${rm.name} (${rm.sku})',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (v) => setState(() {
                                                row.rawMaterialId = v;
                                                final rm = widget.rawMaterials
                                                    .where((m) => m.id == v)
                                                    .firstOrNull;
                                                if (rm != null) {
                                                  row.uom = (rm.unitOfMeasure
                                                              as String?) ??
                                                          row.uom;
                                                }
                                              }),
                                              validator: (v) =>
                                                  (v == null || v.isEmpty)
                                                      ? 'Pick a raw material'
                                                      : null,
                                            )
                                          : DropdownButtonFormField<String>(
                                              decoration: const InputDecoration(
                                                labelText: 'Sub-assembly *',
                                              ),
                                              initialValue: row.rawMaterialId,
                                              items: subAssemblies
                                                  .map<DropdownMenuItem<String>>(
                                                    (p) =>
                                                        DropdownMenuItem<String>(
                                                      value: p.id,
                                                      child: Text(
                                                        '${p.name} (${p.sku})',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (v) => setState(
                                                  () => row.rawMaterialId = v),
                                              validator: (v) =>
                                                  (v == null || v.isEmpty)
                                                      ? 'Pick a sub-assembly'
                                                      : null,
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: row.qtyCtrl,
                                        decoration: InputDecoration(
                                          labelText: 'Qty per Unit *',
                                          suffixText: row.uom,
                                        ),
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        onChanged: (_) => setState(() {}),
                                        validator: (v) {
                                          final n = double.tryParse(v ?? '');
                                          if (n == null || n <= 0) {
                                            return 'Enter qty > 0';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: row.yieldCtrl,
                                        decoration: const InputDecoration(
                                          labelText: 'Yield %',
                                          hintText: '100',
                                          helperText: '15% loss = 85',
                                          suffixText: '%',
                                        ),
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        onChanged: (_) => setState(() {}),
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) {
                                            return null;
                                          }
                                          final n = double.tryParse(v.trim());
                                          if (n == null || n <= 0 || n > 100) {
                                            return '1\u2013100';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Remove row',
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: AppColors.error),
                                      onPressed: () => setState(() {
                                        _bomRows[i].dispose();
                                        _bomRows.removeAt(i);
                                      }),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Builder(builder: (ctx) {
                          // Either inputs are valid starting points for a BOM
                          // row. If neither exists, the Add button is disabled.
                          final hasSubAssemblies = ctx
                              .read<AppState>()
                              .products
                              .any((p) =>
                                  p.manufacturerId != null &&
                                  p.manufacturerId!.isNotEmpty &&
                                  p.id != widget.existingProduct?.id);
                          final canAdd = widget.rawMaterials.isNotEmpty ||
                              hasSubAssemblies;
                          return OutlinedButton.icon(
                            onPressed: !canAdd
                                ? null
                                : () => setState(() {
                                      final preferRaw =
                                          widget.rawMaterials.isNotEmpty;
                                      _bomRows.add(_BomRowState(
                                        kind: preferRaw
                                            ? BomComponentKind.rawMaterial
                                            : BomComponentKind.product,
                                        uom: preferRaw
                                            ? (widget.rawMaterials.first
                                                        .unitOfMeasure
                                                    as String?) ??
                                                'pcs'
                                            : 'pcs',
                                      ));
                                    }),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Material'),
                          );
                        }),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: _save,
          child: Text(_isEdit ? 'Save Changes' : 'Save Product'),
        ),
      ],
    );
  }

  /// Per-warehouse stock table. Shows one row per warehouse with an editable
  /// count and a computed total at the bottom. Replaces the single "Current
  /// Stock" field when [BusinessProfile.isMultiLocation] is true.
  Widget _buildStockByWarehouseField() {
    final warehouses = widget.warehouses;
    int total = 0;
    for (final ctrl in _whStockCtrls.values) {
      total += int.tryParse(ctrl.text) ?? 0;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Stock by Location',
            style: AppTextStyles.bodySmall
                .copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...warehouses.map((w) {
          final ctrl = _whStockCtrls[w.id];
          if (ctrl == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    '${w.name} — ${w.city}',
                    style: AppTextStyles.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: ctrl,
                    decoration: const InputDecoration(
                      suffixText: 'units',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final val = int.tryParse(v ?? '');
                      if (val == null || val < 0) return 'Invalid';
                      return null;
                    },
                  ),
                ),
              ],
            ),
          );
        }),
        const Divider(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total', style: AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w600)),
            Text('$total units',
                style: AppTextStyles.bodySmall
                    .copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // ── Manufactured-product preconditions (Phase 1.4) ───────────────────
    // Cost for a manufactured product is derived from its BOM materials and
    // the per-unit production fee. Saving without a BOM produces a $0 cost
    // that silently pollutes every downstream KPI (inventory cost, margin,
    // EOQ). Catch it at the source instead of letting the user discover it
    // on the dashboard.
    if (_sourceType == _ProductSourceType.manufactured) {
      final appState = context.read<AppState>();
      // A manufactured product needs SOMETHING to build from: either raw
      // materials or sub-assembly products. With neither, the BOM picker is
      // empty and any saved product would have $0 cost.
      final hasSubAssemblies = appState.products.any((p) =>
          p.manufacturerId != null &&
          p.manufacturerId!.isNotEmpty &&
          p.id != widget.existingProduct?.id);
      if (appState.rawMaterials.isEmpty && !hasSubAssemblies) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Add raw materials first — manufactured products need a BOM. '
              'Open Raw Materials, add the inputs, then come back here.',
            ),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Open Raw Materials',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pop(context);
                context.go('/raw-materials');
              },
            ),
          ),
        );
        return;
      }
      final hasUsableBomRow = _bomRows.any((r) =>
          r.rawMaterialId != null &&
          r.rawMaterialId!.isNotEmpty &&
          (double.tryParse(r.qtyCtrl.text.trim()) ?? 0) > 0);
      if (!hasUsableBomRow) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A manufactured product needs at least one BOM material with a '
              'quantity greater than 0. Add a row in "Bill of Materials".',
            ),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
      if (_selectedManufacturerId == null ||
          _selectedManufacturerId!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pick a manufacturer — production orders need someone to send '
              'the work to.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    // Enforce mutual exclusion on save: a product is either purchased from a
    // supplier OR manufactured by a manufacturer, never both. This drives the
    // replenishment branching downstream (PO vs ProductionOrder).
    final supplierId = _sourceType == _ProductSourceType.purchased
        ? _selectedSupplierId
        : null;
    final manufacturerId = _sourceType == _ProductSourceType.manufactured
        ? _selectedManufacturerId
        : null;
    final primaryCost = _sourceType == _ProductSourceType.manufactured
        ? _computedTotalCost
        : (double.tryParse(_costCtrl.text) ?? 0);
    final primaryLeadTime = int.tryParse(_leadTimeCtrl.text) ?? 0;

    // Build the full sourcing options list: primary (isDefault=true) + alts.
    final sourcingOptions = <SourcingOption>[
      SourcingOption(
        kind: _sourceType == _ProductSourceType.manufactured
            ? 'manufacture'
            : 'purchase',
        supplierId: supplierId,
        manufacturerId: manufacturerId,
        unitCost: primaryCost,
        leadTimeDays: primaryLeadTime,
        isDefault: true,
      ),
      ..._altSourcingOptions.map((alt) => SourcingOption(
            kind: 'purchase',
            supplierId: alt.supplierId,
            unitCost: double.tryParse(alt.costCtrl.text.trim()) ?? 0,
            leadTimeDays: int.tryParse(alt.leadTimeCtrl.text.trim()) ?? 0,
            moq: int.tryParse(alt.moqCtrl.text.trim()),
            isDefault: false,
          )),
    ];

    // Build stockByWarehouse from per-warehouse controllers (multi-location).
    // currentStock is the sum so legacy code keeps working unchanged.
    Map<String, int> stockByWarehouse = {};
    int currentStock;
    if (_whStockCtrls.isNotEmpty) {
      for (final entry in _whStockCtrls.entries) {
        final qty = int.tryParse(entry.value.text.trim()) ?? 0;
        if (qty > 0) stockByWarehouse[entry.key] = qty;
      }
      currentStock = stockByWarehouse.isEmpty
          ? 0
          : stockByWarehouse.values.fold(0, (a, b) => a + b);
      // Keep the legacy _stockCtrl in sync so validators don't fire.
      _stockCtrl.text = '$currentStock';
    } else {
      currentStock = int.tryParse(_stockCtrl.text) ?? 0;
    }

    final product = Product(
      id: widget.existingProduct?.id ?? '',
      sku: _skuCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      category: _categoryCtrl.text.trim(),
      // For manufactured products the persisted unitCost is the computed
      // (materials + fee) total so downstream EOQ/replenishment math is correct.
      unitCost: primaryCost,
      currentStock: currentStock,
      supplierId: supplierId,
      manufacturerId: manufacturerId,
      warehouseId: _selectedWarehouseId,
      leadTimeDays: primaryLeadTime,
      sellingPrice: double.tryParse(_sellingPriceCtrl.text.trim()),
      productionFee: _sourceType == _ProductSourceType.manufactured
          ? (double.tryParse(_productionFeeCtrl.text.trim()))
          : null,
      sourcingOptions: sourcingOptions,
      stockByWarehouse: stockByWarehouse,
    );
    final appState = context.read<AppState>();
    try {
      final Product saved;
      if (_isEdit) {
        await appState.updateProduct(product);
        saved = product;
      } else {
        saved = await appState.addProduct(product);
      }

      // ── BOM sync ────────────────────────────────────────────────────────
      // A BOM only makes sense for manufactured products. For purchased
      // products, remove any stale recipe. For manufactured products with no
      // material rows, also remove the BOM (forecasts/replenishment will warn
      // the user separately).
      final existingBom = widget.existingBom;
      if (_sourceType == _ProductSourceType.manufactured &&
          _bomRows.isNotEmpty) {
        final materials = _bomRows
            .where((r) =>
                r.rawMaterialId != null && r.rawMaterialId!.isNotEmpty)
            .map((r) {
              final yp = double.tryParse(r.yieldCtrl.text.trim());
              return BomMaterial(
                rawMaterialId: r.rawMaterialId!,
                quantityPerUnit:
                    double.tryParse(r.qtyCtrl.text.trim()) ?? 0,
                unitOfMeasure: r.uom,
                kind: r.kind,
                yieldPercent:
                    (yp != null && yp > 0 && yp < 100) ? yp : null,
              );
            })
            .where((m) => m.quantityPerUnit > 0)
            .toList();
        if (materials.isNotEmpty) {
          final bom = BillOfMaterials(
            id: existingBom?.id ?? '',
            finalProductId: saved.id,
            materials: materials,
          );
          if (existingBom != null) {
            await appState.updateBOM(bom);
          } else {
            await appState.addBOM(bom);
          }
        } else if (existingBom != null) {
          await appState.deleteBOM(existingBom.id);
        }
      } else if (existingBom != null) {
        await appState.deleteBOM(existingBom.id);
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
    _sellingPriceCtrl.dispose();
    _productionFeeCtrl.dispose();
    _stockCtrl.dispose();
    _leadTimeCtrl.dispose();
    for (final r in _bomRows) {
      r.dispose();
    }
    for (final r in _altSourcingOptions) {
      r.dispose();
    }
    for (final ctrl in _whStockCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }
}
