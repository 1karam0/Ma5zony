import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';
import 'package:ma5zony/widgets/zoho_patterns.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _showBanner = true;
  bool _showChecklist = true;
  bool _syncing = false;
  int _rangeMonths = 6;
  int _selectedTab = 0; // 0 = Dashboard, 1 = Getting Started, 2 = Help

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Count of onboarding tasks remaining (for the tab badge).
  int _remainingOnboardingTasks(AppState state) {
    int remaining = 0;
    if (state.products.isEmpty) remaining++;
    if (state.suppliers.isEmpty) remaining++;
    final allRmHaveSupplier = state.rawMaterials.isNotEmpty &&
        state.rawMaterials.every(
            (r) => r.supplierId != null && r.supplierId!.isNotEmpty);
    if (state.rawMaterials.isEmpty || !allRmHaveSupplier) remaining++;
    final bomProductIds = state.boms.map((b) => b.finalProductId).toSet();
    final allProductsHaveBom = state.products.isNotEmpty &&
        state.products.every((p) => bomProductIds.contains(p.id));
    if (!allProductsHaveBom) remaining++;
    if (state.manufacturers.isEmpty) remaining++;
    final allProductsInWarehouse = state.products.isNotEmpty &&
        state.products.every(
            (p) => p.warehouseId != null && p.warehouseId!.isNotEmpty);
    if (state.warehouses.isEmpty || !allProductsInWarehouse) remaining++;
    if (state.demandByProduct.isEmpty) remaining++;
    if (state.currentForecast == null) remaining++;
    return remaining;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.isLoading) return const Center(child: CircularProgressIndicator());

    final remaining = _remainingOnboardingTasks(state);

    return Column(
      children: [
        HorizontalTabBar(
          selectedIndex: _selectedTab,
          onChanged: (i) => setState(() => _selectedTab = i),
          tabs: [
            const ZohoTab(label: 'Dashboard', icon: Icons.dashboard_outlined),
            ZohoTab(
              label: 'Getting Started',
              icon: Icons.rocket_launch_outlined,
              badge: remaining > 0 ? remaining : null,
            ),
            const ZohoTab(label: 'Help & Support', icon: Icons.help_outline),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _selectedTab,
            children: [
              _buildDashboardTab(context, state),
              _GettingStartedView(
                state: state,
                onGoToHelp: () => setState(() => _selectedTab = 2),
                onConnectShopify: () => context.go('/integrations'),
              ),
              const _HelpSupportView(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardTab(BuildContext context, AppState state) {

    final products = state.products;
    final recommendations = state.recommendations;
    final warehouses = state.warehouses;
    final user = state.currentUser;

    // Derived stats
    final totalUnits = products.fold<int>(0, (s, p) => s + p.currentStock);
    final criticalCount = products.where((p) => p.currentStock == 0).length;
    final lowCount = products.where((p) {
      final rec = recommendations.where((r) => r.productId == p.id).firstOrNull;
      final rop = rec?.reorderPoint ?? 0;
      return p.currentStock > 0 && rop > 0 && p.currentStock <= rop;
    }).length;
    final okCount = products.length - criticalCount - lowCount;
    final hasData = products.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Inline onboarding hint (collapsible) ──────────────────────
          // Full checklist lives on the Getting Started tab. Here we only
          // show a single-line nudge while there are remaining tasks.
          if (_showChecklist && _needsOnboarding(state))
            _OnboardingTabNudge(
              remaining: _remainingOnboardingTasks(state),
              onOpen: () => setState(() => _selectedTab = 1),
              onDismiss: () => setState(() => _showChecklist = false),
            ),

          // ── Greeting header ────────────────────────────────────────────
          if (hasData) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_greeting()}, ${user?.name.split(' ').first ?? 'there'}',
                      style: AppTextStyles.h1,
                    ),
                    Text(
                      DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                      style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const Spacer(),
                // Shopify sync button (compact)
                if (state.shopifyConnection?.isConnected == true)
                  _ShopifySyncChip(
                    syncing: _syncing,
                    domain: state.shopifyConnection!.shopDomain,
                    lastSync: state.shopifyConnection!.lastSyncAt,
                    onSync: () => _syncShopify(context, state),
                  )
                else if (_showBanner)
                  TextButton.icon(
                    onPressed: () => context.go('/integrations'),
                    icon: const Icon(Icons.store, size: 14),
                    label: const Text('Connect Shopify'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          // ── Shopify connect banner (empty state) ───────────────────────
          if (_showBanner && !hasData && state.shopifyConnection?.isConnected != true)
            _ShopifyBanner(
              onConnect: () => context.go('/integrations'),
              onDismiss: () => setState(() => _showBanner = false),
            ),

          // ── Needs Attention ────────────────────────────────────────────
          if (hasData && (criticalCount > 0 || lowCount > 0 || state.openRecommendations > 0))
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _NeedsAttentionPanel(
                criticalCount: criticalCount,
                lowCount: lowCount,
                openRecommendations: state.openRecommendations,
                pendingOrders: state.purchaseOrders
                    .where((o) => o.status.name == 'pending' || o.status.name == 'confirmed')
                    .length,
              ),
            ),

          // ── KPI row ────────────────────────────────────────────────────
          if (hasData) ...[
            _KpiRow(
              totalUnits: totalUnits,
              lowStockItems: state.lowStockItems,
              openRecommendations: state.openRecommendations,
              forecastAccuracy: state.forecastAccuracy,
            ),
            const SizedBox(height: 16),

            // Critical stock alert banner
            if (state.hasUrgentStockAlerts)
              _CriticalStockBanner(state: state),
            if (state.hasUrgentStockAlerts)
              const SizedBox(height: 16),

            // Stock health bar
            _StockHealthBar(
              okCount: okCount,
              lowCount: lowCount,
              criticalCount: criticalCount,
              total: products.length,
            ),
            const SizedBox(height: 24),
          ],

          // ── Charts ─────────────────────────────────────────────────────
          if (hasData)
            LayoutBuilder(builder: (context, constraints) {
              final isWide = constraints.maxWidth > 1000;
              final demandCard = _DemandForecastCard(
                state: state,
                rangeMonths: _rangeMonths,
                onRangeChanged: (v) => setState(() => _rangeMonths = v),
              );
              final stockCard = _StockByWarehouseCard(warehouses: warehouses);

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: demandCard),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: stockCard),
                  ],
                );
              }
              return Column(children: [
                demandCard,
                const SizedBox(height: 20),
                stockCard,
              ]);
            }),

          if (hasData) const SizedBox(height: 24),

          // ── Inventory overview table ───────────────────────────────────
          if (hasData)
            _InventoryOverviewTable(
              products: products,
              recommendations: recommendations,
            ),

          // ── Empty state ────────────────────────────────────────────────
          if (!hasData && !_needsOnboarding(state))
            _EmptyDashboard(),
        ],
      ),
    );
  }

  bool _needsOnboarding(AppState state) {
    if (state.products.isEmpty) return true;
    if (state.suppliers.isEmpty) return true;
    if (state.rawMaterials.isEmpty) return true;
    final bomProductIds = state.boms.map((b) => b.finalProductId).toSet();
    if (state.products.any((p) => !bomProductIds.contains(p.id))) return true;
    if (state.manufacturers.isEmpty) return true;
    if (state.products.any((p) => p.warehouseId == null || p.warehouseId!.isEmpty)) return true;
    if (state.demandByProduct.isEmpty) return true;
    if (state.currentForecast == null) return true;
    return false;
  }

  Future<void> _syncShopify(BuildContext context, AppState state) async {
    setState(() => _syncing = true);
    try {
      await state.syncShopifyInventory();
      final orderResult = await state.importShopifyOrders();
      if (context.mounted) {
        final imported = orderResult?['newRecordsImported'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('Shopify synced! $imported new demand records imported.'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 3), content: Text('Sync failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }
}

// ── Critical Stock Alert Banner ────────────────────────────────────────────────

class _CriticalStockBanner extends StatefulWidget {
  final AppState state;
  const _CriticalStockBanner({required this.state});

  @override
  State<_CriticalStockBanner> createState() => _CriticalStockBannerState();
}

class _CriticalStockBannerState extends State<_CriticalStockBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final critical = widget.state.criticalStockProducts;
    final mostUrgent = critical.isNotEmpty ? critical.first : null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${critical.length} product${critical.length > 1 ? 's are' : ' is'} critically low'
                    ' — estimated stockout in < 5 days',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                        fontSize: 13),
                  ),
                ),
                if (mostUrgent != null)
                  TextButton(
                    onPressed: () => context.go(
                        '/forecasts?productId=${mostUrgent.productId}'),
                    child: const Text('Run Forecast Now →',
                        style: TextStyle(color: AppColors.error)),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16,
                      color: AppColors.error),
                  onPressed: () => setState(() => _dismissed = true),
                ),
              ],
            ),
          ),
          // Critical products table
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1.5),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(1.2),
                3: FlexColumnWidth(1.2),
                4: FlexColumnWidth(1),
                5: FlexColumnWidth(1.5),
              },
              children: [
                TableRow(
                  children: [
                    'SKU', 'Product', 'Current', 'Min Stock', 'Days Left', ''
                  ]
                      .map((h) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(h,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.error)),
                          ))
                      .toList(),
                ),
                ...critical.take(5).map((r) => TableRow(
                      children: [
                        Text(r.sku,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textPrimary)),
                        Text(r.productName,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textPrimary)),
                        Text('${r.currentStock} u',
                            style: const TextStyle(fontSize: 12)),
                        Text('${r.minimumStock} u',
                            style: const TextStyle(fontSize: 12)),
                        Text(
                            '${r.daysOfStockLeft.toStringAsFixed(0)} d',
                            style: TextStyle(
                                fontSize: 12,
                                color: r.daysOfStockLeft < 3
                                    ? AppColors.error
                                    : AppColors.warning,
                                fontWeight: FontWeight.w700)),
                        GestureDetector(
                          onTap: () => context
                              .go('/forecasts?productId=${r.productId}'),
                          child: const Text('Forecast →',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ].map((w) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: w,
                          )).toList(),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Onboarding checklist ────────────────────────────────────────────────────

class _OnboardingChecklist extends StatelessWidget {
  final AppState state;
  final VoidCallback onDismiss;

  const _OnboardingChecklist({required this.state, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    // Check BOM coverage: how many products have an active BOM
    final bomProductIds = state.boms.map((b) => b.finalProductId).toSet();
    final allProductsHaveBom = state.products.isNotEmpty &&
        state.products.every((p) => bomProductIds.contains(p.id));
    // Check if all raw materials have a supplier
    final allRmHaveSupplier = state.rawMaterials.isNotEmpty &&
        state.rawMaterials.every((r) => r.supplierId != null && r.supplierId!.isNotEmpty);
    // Check if all products are assigned to a warehouse
    final allProductsInWarehouse = state.products.isNotEmpty &&
        state.products.every((p) => p.warehouseId != null && p.warehouseId!.isNotEmpty);

    final steps = [
      (
        'Add your products',
        'Start by adding the products you sell (SKU, stock, price). These are the center of your supply chain.',
        '/products',
        state.products.isNotEmpty,
        Icons.inventory_2_outlined,
      ),
      (
        'Add your suppliers',
        'Add the companies you buy raw materials from. Each supplier has a lead time that affects how early you need to order.',
        '/suppliers',
        state.suppliers.isNotEmpty,
        Icons.local_shipping_outlined,
      ),
      (
        'Add raw materials',
        'Raw materials are the ingredients your products are made from. Link each one to a supplier.',
        '/raw-materials',
        state.rawMaterials.isNotEmpty && allRmHaveSupplier,
        Icons.category_outlined,
      ),
      (
        'Set up Bills of Materials',
        'A Bill of Materials (BOM) defines which raw materials — and how much of each — go into making one unit of a product.',
        '/bom',
        allProductsHaveBom,
        Icons.account_tree_outlined,
      ),
      (
        'Add a manufacturer',
        'The manufacturer takes your raw materials and produces the finished product. Add production capacity and lead time.',
        '/manufacturers',
        state.manufacturers.isNotEmpty,
        Icons.factory_outlined,
      ),
      (
        'Assign products to a warehouse',
        'Warehouses track where your finished goods are stored. Assign products so stock levels are location-aware.',
        '/warehouses',
        state.warehouses.isNotEmpty && allProductsInWarehouse,
        Icons.warehouse_outlined,
      ),
      (
        'Import sales / demand history',
        'Upload past sales so the forecasting algorithms have data to learn from. You can also sync from Shopify.',
        '/demand-data',
        state.demandByProduct.isNotEmpty,
        Icons.show_chart,
      ),
      (
        'Run your first forecast',
        'Generate a demand forecast and let Ma5zony recommend reorder points, safety stock, and order quantities.',
        '/forecasts',
        state.currentForecast != null,
        Icons.query_stats,
      ),
    ];

    final doneCount = steps.where((s) => s.$4).length;
    if (doneCount == steps.length) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.06),
            AppColors.secondary.withValues(alpha: 0.5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rocket_launch_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Get started — $doneCount of ${steps.length} complete',
                style: AppTextStyles.h3.copyWith(color: AppColors.primary),
              ),
              const Spacer(),
              SizedBox(
                width: 100,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: doneCount / steps.length,
                    minHeight: 6,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${(doneCount / steps.length * 100).toInt()}%',
                  style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Complete these steps in order — each one unlocks the next part of your supply chain.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ...steps.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            final isDone = s.$4;
            // A step is locked if the previous step isn't done
            final isLocked = i > 0 && !steps[i - 1].$4;
            final isNext = !isDone && !isLocked && (i == 0 || steps[i - 1].$4);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: (isDone || isLocked) ? null : () => context.go(s.$3),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDone
                        ? AppColors.success.withValues(alpha: 0.06)
                        : isNext
                            ? Colors.white
                            : AppColors.background,
                    border: Border.all(
                      color: isDone
                          ? AppColors.success.withValues(alpha: 0.35)
                          : isNext
                              ? AppColors.primary.withValues(alpha: 0.4)
                              : AppColors.border.withValues(alpha: 0.5),
                      width: isNext ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      // Step number / check circle
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? AppColors.success.withValues(alpha: 0.15)
                              : isNext
                                  ? AppColors.primary.withValues(alpha: 0.12)
                                  : AppColors.border.withValues(alpha: 0.5),
                        ),
                        child: Center(
                          child: isDone
                              ? const Icon(Icons.check, size: 14, color: AppColors.success)
                              : isLocked
                                  ? const Icon(Icons.lock_outline, size: 13, color: AppColors.textSecondary)
                                  : Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isNext ? AppColors.primary : AppColors.textSecondary,
                                      ),
                                    ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  s.$1,
                                  style: AppTextStyles.body.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isDone
                                        ? AppColors.success
                                        : isLocked
                                            ? AppColors.textSecondary
                                            : AppColors.textPrimary,
                                    decoration: isDone ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                if (isNext) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('Next step',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ],
                            ),
                            if (!isDone && !isLocked)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  s.$2,
                                  style: AppTextStyles.bodySmall
                                      .copyWith(color: AppColors.textSecondary),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Arrow
                      if (!isDone && !isLocked)
                        const Icon(Icons.chevron_right, size: 18, color: AppColors.primary),
                      if (isLocked)
                        const SizedBox(width: 18),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Shopify banner ──────────────────────────────────────────────────────────

class _ShopifyBanner extends StatelessWidget {
  final VoidCallback onConnect;
  final VoidCallback onDismiss;
  const _ShopifyBanner({required this.onConnect, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.store, color: AppColors.primary, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Connect your Shopify store', style: AppTextStyles.h3),
            Text(
              'Automatically sync products, orders, and inventory in real-time.',
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
          ]),
        ),
        ElevatedButton(
          onPressed: onConnect,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Connect Store'),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: onDismiss,
          color: AppColors.textSecondary,
        ),
      ]),
    );
  }
}

// ── Shopify sync chip ───────────────────────────────────────────────────────

class _ShopifySyncChip extends StatelessWidget {
  final bool syncing;
  final String domain;
  final DateTime? lastSync;
  final VoidCallback onSync;

  const _ShopifySyncChip({
    required this.syncing,
    required this.domain,
    required this.lastSync,
    required this.onSync,
  });

  String _ago(DateTime? dt) {
    if (dt == null) return 'never synced';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'synced just now';
    if (diff.inMinutes < 60) return 'synced ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'synced ${diff.inHours}h ago';
    return 'synced ${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.store, color: AppColors.success, size: 14),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(domain,
                style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, fontSize: 11)),
            Text(_ago(lastSync),
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSubdued, fontSize: 10)),
          ],
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 28,
          child: ElevatedButton.icon(
            onPressed: syncing ? null : onSync,
            icon: syncing
                ? const SizedBox(width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync, size: 12),
            label: Text(syncing ? 'Syncing…' : 'Sync',
                style: const TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Needs Attention panel ───────────────────────────────────────────────────

class _NeedsAttentionPanel extends StatelessWidget {
  final int criticalCount;
  final int lowCount;
  final int openRecommendations;
  final int pendingOrders;

  const _NeedsAttentionPanel({
    required this.criticalCount,
    required this.lowCount,
    required this.openRecommendations,
    required this.pendingOrders,
  });

  @override
  Widget build(BuildContext context) {
    final items = <_AttentionItem>[];
    if (criticalCount > 0) {
      items.add(_AttentionItem(
        icon: Icons.error_outline,
        color: AppColors.error,
        label: '$criticalCount product${criticalCount > 1 ? 's' : ''} out of stock',
        cta: 'Order now',
        route: '/replenishment',
      ));
    }
    if (lowCount > 0) {
      items.add(_AttentionItem(
        icon: Icons.warning_amber,
        color: AppColors.warning,
        label: '$lowCount product${lowCount > 1 ? 's' : ''} below reorder point',
        cta: 'Review',
        route: '/replenishment',
      ));
    }
    if (openRecommendations > 0) {
      items.add(_AttentionItem(
        icon: Icons.assignment_late_outlined,
        color: AppColors.primary,
        label: '$openRecommendations replenishment recommendation${openRecommendations > 1 ? 's' : ''} pending approval',
        cta: 'Approve',
        route: '/replenishment',
      ));
    }
    if (pendingOrders > 0) {
      items.add(_AttentionItem(
        icon: Icons.receipt_long_outlined,
        color: AppColors.accent,
        label: '$pendingOrders purchase order${pendingOrders > 1 ? 's' : ''} awaiting action',
        cta: 'View orders',
        route: '/orders',
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.04),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.notifications_active_outlined, size: 15, color: AppColors.error),
            const SizedBox(width: 6),
            Text(
              'Needs your attention today',
              style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.error),
            ),
          ]),
          const SizedBox(height: 10),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(item.icon, size: 14, color: item.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.label,
                    style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500)),
              ),
              TextButton(
                onPressed: () => context.go(item.route),
                style: TextButton.styleFrom(
                  foregroundColor: item.color,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(item.cta),
              ),
            ]),
          )),
        ],
      ),
    );
  }
}

class _AttentionItem {
  final IconData icon;
  final Color color;
  final String label;
  final String cta;
  final String route;
  const _AttentionItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.cta,
    required this.route,
  });
}

// ── KPI Row ─────────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  final int totalUnits;
  final int lowStockItems;
  final int openRecommendations;
  final double forecastAccuracy;

  const _KpiRow({
    required this.totalUnits,
    required this.lowStockItems,
    required this.openRecommendations,
    required this.forecastAccuracy,
  });

  @override
  Widget build(BuildContext context) {
    final accuracy = forecastAccuracy > 0
        ? '${(forecastAccuracy * 100).toStringAsFixed(1)}%'
        : 'N/A';

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final cols = w > 800 ? 4 : w > 500 ? 2 : 1;
      const spacing = 14.0;
      final cardW = (w - spacing * (cols - 1)) / cols;

      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          SizedBox(
            width: cardW,
            child: KPICard(
              title: 'Total Units in Stock',
              value: NumberFormat.compact().format(totalUnits),
              icon: Icons.inventory_2,
              onTap: () => context.go('/products'),
            ),
          ),
          SizedBox(
            width: cardW,
            child: KPICard(
              title: 'Items Below ROP',
              value: '$lowStockItems',
              icon: Icons.warning_amber,
              isAlert: lowStockItems > 0,
              color: lowStockItems > 0 ? AppColors.warning : AppColors.success,
              onTap: () => context.go('/replenishment'),
            ),
          ),
          SizedBox(
            width: cardW,
            child: KPICard(
              title: 'Open Recommendations',
              value: '$openRecommendations',
              icon: Icons.assignment_late,
              color: openRecommendations > 0 ? AppColors.primary : AppColors.textSecondary,
              onTap: () => context.go('/replenishment'),
            ),
          ),
          SizedBox(
            width: cardW,
            child: KPICard(
              title: 'Forecast Accuracy',
              value: accuracy,
              icon: Icons.auto_graph,
              color: forecastAccuracy > 0.9
                  ? AppColors.success
                  : forecastAccuracy > 0.75
                      ? AppColors.warning
                      : AppColors.textSecondary,
            ),
          ),
        ],
      );
    });
  }
}

// ── Stock health bar ────────────────────────────────────────────────────────

class _StockHealthBar extends StatelessWidget {
  final int okCount;
  final int lowCount;
  final int criticalCount;
  final int total;

  const _StockHealthBar({
    required this.okCount,
    required this.lowCount,
    required this.criticalCount,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Stock Health', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            _HealthChip(color: AppColors.success, label: '$okCount OK'),
            const SizedBox(width: 8),
            _HealthChip(color: AppColors.warning, label: '$lowCount Low'),
            const SizedBox(width: 8),
            _HealthChip(color: AppColors.error, label: '$criticalCount Critical'),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(children: [
                if (okCount > 0)
                  Flexible(
                    flex: okCount,
                    child: Container(color: AppColors.success),
                  ),
                if (lowCount > 0)
                  Flexible(
                    flex: lowCount,
                    child: Container(color: AppColors.warning),
                  ),
                if (criticalCount > 0)
                  Flexible(
                    flex: criticalCount,
                    child: Container(color: AppColors.error),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthChip extends StatelessWidget {
  final Color color;
  final String label;
  const _HealthChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: AppTextStyles.bodySmall.copyWith(fontSize: 11)),
    ]);
  }
}

// ── Demand Forecast Chart Card ──────────────────────────────────────────────

class _DemandForecastCard extends StatelessWidget {
  final AppState state;
  final int rangeMonths;
  final ValueChanged<int> onRangeChanged;

  const _DemandForecastCard({
    required this.state,
    required this.rangeMonths,
    required this.onRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  'Demand vs Forecast — Last ${rangeMonths}M',
                  style: AppTextStyles.h3,
                ),
              ),
              _RangePicker(selected: rangeMonths, onChanged: onRangeChanged),
            ]),
            const SizedBox(height: 6),
            Text(
              state.currentForecast != null
                  ? 'Showing ${state.currentForecast!.algorithm} forecast overlay'
                  : 'Run a forecast on the Forecasts page to see the overlay',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSubdued),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 240,
              child: _buildChart(state, rangeMonths),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(AppState state, int rangeMonths) {
    final cutoff = DateTime.now().subtract(Duration(days: rangeMonths * 30));
    final forecast = state.currentForecast;

    if (forecast == null || forecast.periods.isEmpty) {
      final allDemand = (state.demandByProduct.values.isNotEmpty
              ? state.demandByProduct.values.first
              : <DomainDemandRecord>[])
          .where((r) => r.periodStart.isAfter(cutoff))
          .toList()
        ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
      final spots = allDemand
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value.quantity.toDouble()))
          .toList();

      return LineChart(LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.borderLight, strokeWidth: 1),
        ),
        titlesData: const FlTitlesData(
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true, border: Border.all(color: AppColors.border)),
        lineBarsData: [
          if (spots.isNotEmpty)
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.primary,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
            ),
        ],
      ));
    }

    final filteredIndices = forecast.periods
        .asMap()
        .entries
        .where((e) => e.value.isAfter(cutoff))
        .map((e) => e.key)
        .toList();

    FlSpot toSpot(int idx, double v) =>
        FlSpot(filteredIndices.indexOf(idx).toDouble(), v);

    final actualSpots = filteredIndices
        .where((i) => i < forecast.actualDemand.length && forecast.actualDemand[i] > 0)
        .map((i) => toSpot(i, forecast.actualDemand[i]))
        .toList();
    final forecastSpots = filteredIndices
        .where((i) => i < forecast.forecast.length && forecast.forecast[i] > 0)
        .map((i) => toSpot(i, forecast.forecast[i]))
        .toList();

    return LineChart(LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.borderLight, strokeWidth: 1),
      ),
      titlesData: const FlTitlesData(
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: true, border: Border.all(color: AppColors.border)),
      lineBarsData: [
        if (actualSpots.isNotEmpty)
          LineChartBarData(
            spots: actualSpots,
            isCurved: true,
            color: AppColors.textSecondary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
                show: true, color: AppColors.primary.withValues(alpha: 0.05)),
          ),
        if (forecastSpots.isNotEmpty)
          LineChartBarData(
            spots: forecastSpots,
            isCurved: true,
            color: AppColors.primary,
            barWidth: 3,
            dashArray: [5, 5],
            dotData: const FlDotData(show: false),
          ),
      ],
    ));
  }
}

// ── Stock by Warehouse chart ────────────────────────────────────────────────

class _StockByWarehouseCard extends StatelessWidget {
  final List warehouses;
  const _StockByWarehouseCard({required this.warehouses});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stock by Warehouse', style: AppTextStyles.h3),
            const SizedBox(height: 6),
            Text('Total stock units per location',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSubdued)),
            const SizedBox(height: 16),
            if (warehouses.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text('No warehouses added yet',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSubdued)),
                ),
              )
            else
              SizedBox(
                height: 200,
                child: BarChart(BarChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= warehouses.length) return const SizedBox.shrink();
                          final name = warehouses[idx].name as String;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              name.length > 8 ? '${name.substring(0, 7)}…' : name,
                              style: const TextStyle(fontSize: 10, color: AppColors.textSubdued),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: warehouses.asMap().entries.map((e) {
                    final colors = [AppColors.primary, AppColors.accent, AppColors.info, AppColors.success];
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: (e.value.totalStock as int).toDouble(),
                          color: colors[e.key % colors.length],
                          width: 28,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }).toList(),
                )),
              ),
            const SizedBox(height: 8),
            ...warehouses.asMap().entries.map((e) {
              final colors = [AppColors.primary, AppColors.accent, AppColors.info, AppColors.success];
              return Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                        color: colors[e.key % colors.length], shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('${e.value.name}: ${e.value.totalStock} units',
                      style: AppTextStyles.label),
                ]),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── Inventory overview table ────────────────────────────────────────────────

class _InventoryOverviewTable extends StatelessWidget {
  final List products;
  final List recommendations;

  const _InventoryOverviewTable({required this.products, required this.recommendations});

  @override
  Widget build(BuildContext context) {
    final rows = products.take(8).map((p) {
      final rec = recommendations.where((r) => r.productId == p.id).firstOrNull;
      final rop = rec?.reorderPoint ?? 0;
      final suggested = rec?.suggestedOrderQty ?? 0;
      final urgency = rec?.urgency as String? ?? '';

      String status;
      Color statusColor;
      if (p.currentStock == 0) {
        status = 'Critical';
        statusColor = AppColors.error;
      } else if (rop > 0 && p.currentStock <= rop) {
        status = 'Low';
        statusColor = AppColors.warning;
      } else {
        status = 'OK';
        statusColor = AppColors.success;
      }

      return (p, rop, suggested, urgency, status, statusColor);
    }).toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Inventory Overview', style: AppTextStyles.h3),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context.go('/products'),
                icon: const Icon(Icons.open_in_new, size: 13),
                label: const Text('View all'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Showing top ${rows.length} products with stock status',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSubdued),
            ),
            const SizedBox(height: 12),
            HorizontallyScrollableTable(
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AppColors.background),
                dataRowMinHeight: 44,
                dataRowMaxHeight: 56,
                columns: const [
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('Stock'), numeric: true),
                  DataColumn(label: Text('ROP'), numeric: true),
                  DataColumn(label: Text('Suggested Qty'), numeric: true),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Action')),
                ],
                rows: rows.map((r) {
                  final (p, rop, suggested, urgency, status, statusColor) = r;
                  return DataRow(cells: [
                    DataCell(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(p.name,
                            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                        Text(p.sku, style: AppTextStyles.label.copyWith(fontSize: 10)),
                      ],
                    )),
                    DataCell(Text('${p.currentStock}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: status == 'Critical'
                              ? AppColors.error
                              : status == 'Low'
                                  ? AppColors.warning
                                  : AppColors.textPrimary,
                        ))),
                    DataCell(Text('$rop')),
                    DataCell(Text(suggested > 0 ? '$suggested' : '—')),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(status,
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                    )),
                    DataCell(
                      status == 'OK'
                          ? const Text('—', style: TextStyle(color: AppColors.textSubdued))
                          : TextButton(
                              onPressed: () => context.go('/replenishment'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                textStyle: const TextStyle(fontSize: 11),
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Order →'),
                            ),
                    ),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────

class _EmptyDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            const Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.border),
            const SizedBox(height: 16),
            Text('No data yet', style: AppTextStyles.h2),
            const SizedBox(height: 8),
            Text(
              'Add products to get started with inventory tracking.',
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => context.go('/products'),
              icon: const Icon(Icons.add),
              label: const Text('Add Products'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Range Picker ─────────────────────────────────────────────────────────────

class _RangePicker extends StatelessWidget {
  const _RangePicker({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;
  static const _options = [1, 3, 6, 12];

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: _options
          .map((m) => ButtonSegment<int>(value: m, label: Text('${m}M')))
          .toList(),
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

// ── Onboarding Tab Nudge ─────────────────────────────────────────────────────
// Small dismissible banner on the Dashboard tab pointing users to the
// dedicated Getting Started tab.

class _OnboardingTabNudge extends StatelessWidget {
  final int remaining;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  const _OnboardingTabNudge({
    required this.remaining,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        borderRadius: AppRadius.md,
      ),
      child: Row(
        children: [
          const Icon(Icons.rocket_launch_outlined,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You have $remaining setup task${remaining == 1 ? '' : 's'} '
              'remaining. Finish them in the Getting Started tab.',
              style: AppTextStyles.body
                  .copyWith(color: AppColors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: onOpen,
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Open'),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onDismiss,
            color: AppColors.textSecondary,
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}

// ── Getting Started View ─────────────────────────────────────────────────────
// Dedicated tab body with hero card + full onboarding checklist + setup
// shortcuts + help support callout.

class _GettingStartedView extends StatelessWidget {
  final AppState state;
  final VoidCallback onGoToHelp;
  final VoidCallback onConnectShopify;

  const _GettingStartedView({
    required this.state,
    required this.onGoToHelp,
    required this.onConnectShopify,
  });

  int _remaining() {
    int remaining = 0;
    if (state.products.isEmpty) remaining++;
    if (state.suppliers.isEmpty) remaining++;
    final allRmHaveSupplier = state.rawMaterials.isNotEmpty &&
        state.rawMaterials.every(
            (r) => r.supplierId != null && r.supplierId!.isNotEmpty);
    if (state.rawMaterials.isEmpty || !allRmHaveSupplier) remaining++;
    final bomProductIds = state.boms.map((b) => b.finalProductId).toSet();
    final allProductsHaveBom = state.products.isNotEmpty &&
        state.products.every((p) => bomProductIds.contains(p.id));
    if (!allProductsHaveBom) remaining++;
    if (state.manufacturers.isEmpty) remaining++;
    final allProductsInWarehouse = state.products.isNotEmpty &&
        state.products.every(
            (p) => p.warehouseId != null && p.warehouseId!.isNotEmpty);
    if (state.warehouses.isEmpty || !allProductsInWarehouse) remaining++;
    if (state.demandByProduct.isEmpty) remaining++;
    if (state.currentForecast == null) remaining++;
    return remaining;
  }

  @override
  Widget build(BuildContext context) {
    const totalTasks = 8;
    final remaining = _remaining();
    final done = totalTasks - remaining;
    final userName = state.currentUser?.name.split(' ').first ?? 'there';
    final shopifyConnected = state.shopifyConnection?.isConnected == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GettingStartedHeroCard(
            userName: userName,
            emoji: '👋',
            subtitle: remaining == 0
                ? 'You\'ve completed all setup tasks. Your supply chain is ready to go.'
                : 'Welcome to Ma5zony. Let\'s finish setting up your supply chain.',
            doneCount: done,
            totalCount: totalTasks,
          ),
          const SizedBox(height: 24),

          // Full checklist (never dismissable here — this is its home)
          _OnboardingChecklist(state: state, onDismiss: () {}),

          const SizedBox(height: 8),

          // Setup Your Inventory shortcuts
          Text('Setup Your Inventory', style: AppTextStyles.h3),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (ctx, c) {
            final isWide = c.maxWidth > 720;
            final cards = [
              SetupActionCard(
                icon: Icons.store_outlined,
                title: shopifyConnected ? 'Shopify Connected' : 'Connect Shopify',
                subtitle: shopifyConnected
                    ? 'Store: ${state.shopifyConnection!.shopDomain}'
                    : 'Sync products, inventory, and sales automatically.',
                ctaLabel: shopifyConnected ? 'Manage' : 'Connect',
                onTap: onConnectShopify,
              ),
              SetupActionCard(
                icon: Icons.group_outlined,
                title: 'Invite Your Team',
                subtitle: 'Add inventory managers, manufacturers, or owners.',
                ctaLabel: 'Open',
                onTap: () => context.go('/settings'),
              ),
              SetupActionCard(
                icon: Icons.settings_outlined,
                title: 'Workspace Settings',
                subtitle: 'Configure currency, timezone, and business profile.',
                ctaLabel: 'Open',
                onTap: () => context.go('/settings'),
              ),
            ];
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            }
            return Column(
              children: [
                for (int i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  cards[i],
                ],
              ],
            );
          }),

          const SizedBox(height: 24),
          HelpSupportCard(onTap: onGoToHelp),
        ],
      ),
    );
  }
}

// ── Help & Support View ──────────────────────────────────────────────────────

class _HelpSupportView extends StatelessWidget {
  const _HelpSupportView();

  @override
  Widget build(BuildContext context) {
    final topics = [
      (
        Icons.inventory_2_outlined,
        'Products & SKUs',
        'How to add products, set SKUs, and link them to warehouses.',
      ),
      (
        Icons.account_tree_outlined,
        'Bills of Materials',
        'Define which raw materials are consumed when you produce a finished good.',
      ),
      (
        Icons.show_chart,
        'Forecasting',
        'Run demand forecasts (SMA / SES) and read accuracy metrics.',
      ),
      (
        Icons.local_shipping_outlined,
        'Purchase Orders',
        'Generate POs from reorder recommendations and track delivery.',
      ),
      (
        Icons.store_outlined,
        'Shopify Integration',
        'Connect a store, sync inventory, and import order history.',
      ),
      (
        Icons.factory_outlined,
        'Manufacturing Workflow',
        'Move production orders through Draft → Approved → In Production.',
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Help & Support', style: AppTextStyles.h1),
          const SizedBox(height: 4),
          Text(
            'Browse common topics, watch quick tutorials, or contact our team.',
            style: AppTextStyles.body
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),

          // Quick contact row
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              border: Border.all(color: AppColors.borderSubtle),
              borderRadius: AppRadius.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: AppRadius.sm,
                  ),
                  child: const Icon(Icons.mail_outline,
                      size: 22, color: AppColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Contact Support',
                          style: AppTextStyles.body
                              .copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        'support@ma5zony.com — typical response within 1 business day.',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text('Common Topics', style: AppTextStyles.h3),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (ctx, c) {
            final cols = c.maxWidth > 900
                ? 3
                : c.maxWidth > 600
                    ? 2
                    : 1;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: topics.map((t) {
                return SizedBox(
                  width: (c.maxWidth - (cols - 1) * 12) / cols,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      border: Border.all(color: AppColors.borderSubtle),
                      borderRadius: AppRadius.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(t.$1,
                                size: 18, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(t.$2,
                                  style: AppTextStyles.body.copyWith(
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(t.$3,
                            style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          }),

          const SizedBox(height: 24),
          Text(
            'Ma5zony · Version 1.0 · ${DateTime.now().year}',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSubdued),
          ),
        ],
      ),
    );
  }
}
