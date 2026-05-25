import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/features/onboarding/welcome_tour.dart';
import 'package:ma5zony/models/production_order.dart';
import 'package:ma5zony/models/purchase_order.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';
import 'package:ma5zony/widgets/zoho_patterns.dart';

/// Dashboard shown only to users with the **SME Owner** role.
///
/// Includes financial KPIs (inventory value, COGS, holding costs, open order
/// cost), operational KPIs, revenue-vs-cost chart, inventory value chart,
/// cash-flow projection, and breakdown tables.
class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  bool _showBanner = true;
  bool _showChecklist = true;
  int _selectedTab = 0; // 0=Dashboard, 1=Getting Started, 2=Help
  bool _tourCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    // After the first frame, auto-show the welcome tour for brand-new users
    // (those who have just finished the business-profile wizard and never
    // seen the tour). `tourCompleted` is persisted in UserSettings.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTour());
  }

  Future<void> _maybeShowTour() async {
    if (_tourCheckScheduled) return;
    _tourCheckScheduled = true;
    if (!mounted) return;
    final state = context.read<AppState>();
    // Wait for settings to finish loading (they load asynchronously after
    // sign-in). If still loading, retry shortly.
    if (state.isLoading) {
      Future.delayed(const Duration(milliseconds: 600), () {
        _tourCheckScheduled = false;
        if (mounted) _maybeShowTour();
      });
      return;
    }
    // If tourCompleted is set but the user has zero setup data, the flag was
    // probably written before they finished onboarding (e.g. they refreshed
    // mid-tour). Reset and show the tour again.
    final setupEmpty = state.suppliers.isEmpty &&
        state.products.isEmpty &&
        state.warehouses.isEmpty;
    if (state.settings.tourCompleted && !setupEmpty) return;

    if (mounted) {
      await WelcomeTourDialog.show(context);
    }
  }

  /// Remaining onboarding tasks count (drives the tab badge).
  int _remainingTasks(AppState state) {
    int remaining = 0;
    if (state.products.isEmpty) remaining++;
    if (state.suppliers.isEmpty) remaining++;
    if (state.warehouses.isEmpty) remaining++;
    if (state.demandByProduct.isEmpty) remaining++;
    if (state.currentForecast == null) remaining++;
    if (state.settings.orderingCost == 250.0 &&
        state.settings.holdingRate == 0.20) {
      remaining++;
    }
    return remaining;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Monthly COGS estimate = Σ(demand qty last 30 days × effective unit cost).
  /// Uses [AppState.effectiveUnitCost] so manufactured products are valued at
  /// their rolled-up BOM cost (raw materials + production fee), not the
  /// often-zero manual unitCost field.
  double _monthlyCOGS(AppState state) {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final activeIds = {for (final p in state.products) p.id};
    double cogs = 0;
    for (final entry in state.demandByProduct.entries) {
      if (!activeIds.contains(entry.key)) continue;
      final product =
          state.products.where((p) => p.id == entry.key).firstOrNull;
      if (product == null) continue;
      final unitCost = state.effectiveUnitCost(product);
      for (final d in entry.value) {
        if (d.periodStart.isAfter(thirtyDaysAgo)) {
          cogs += d.quantity * unitCost;
        }
      }
    }
    return cogs;
  }

  /// Estimated monthly holding cost = inventory value × annual holding rate / 12.
  double _monthlyHoldingCost(AppState state) {
    final annualHoldingRate = state.settings.holdingRate;
    return state.totalStockValue * annualHoldingRate / 12;
  }

  /// Open order cost = Σ(suggestedQty × effective unit cost) for all open
  /// recommendations. Uses [AppState.effectiveUnitCost] so manufactured items
  /// are valued via their BOM rollup, keeping the figure consistent with the
  /// Inventory Cost KPI shown alongside it.
  double _openOrderCost(AppState state) {
    double total = 0;
    for (final rec in state.recommendations) {
      final product =
          state.products.where((p) => p.id == rec.productId).firstOrNull;
      if (product != null) {
        total += rec.suggestedOrderQty * state.effectiveUnitCost(product);
      }
    }
    return total;
  }

  /// Total units in stock.
  int _totalUnits(AppState state) =>
      state.products.fold<int>(0, (s, p) => s + p.currentStock);

  /// Products sorted by monthly projected spend (forecast × unitCost) desc.
  List<_ProductSpend> _topExpenseProducts(AppState state) {
    final result = <_ProductSpend>[];
    for (final p in state.products) {
      final rec =
          state.recommendations.where((r) => r.productId == p.id).firstOrNull;
      final forecast = rec?.forecastNextPeriod ?? 0;
      result.add(_ProductSpend(
        name: p.name,
        sku: p.sku,
        monthlyForecast: forecast,
        unitCost: p.unitCost,
        monthlySpend: forecast * p.unitCost,
      ));
    }
    result.sort((a, b) => b.monthlySpend.compareTo(a.monthlySpend));
    return result;
  }

  /// Supplier cost breakdown.
  List<_SupplierCost> _supplierCostBreakdown(AppState state) {
    final map = <String, _SupplierCost>{};
    for (final p in state.products) {
      final supplierId = p.supplierId;
      if (supplierId == null) continue;
      final supplier =
          state.suppliers.where((s) => s.id == supplierId).firstOrNull;
      final name = supplier?.name ?? 'Unknown';
      final leadTime = supplier?.typicalLeadTimeDays ?? 0;
      final rec =
          state.recommendations.where((r) => r.productId == p.id).firstOrNull;
      final spend = (rec?.forecastNextPeriod ?? 0) * p.unitCost;

      if (map.containsKey(supplierId)) {
        map[supplierId] = _SupplierCost(
          name: name,
          productCount: map[supplierId]!.productCount + 1,
          avgLeadTime: ((map[supplierId]!.avgLeadTime *
                      map[supplierId]!.productCount) +
                  leadTime) /
              (map[supplierId]!.productCount + 1),
          totalMonthlySpend: map[supplierId]!.totalMonthlySpend + spend,
        );
      } else {
        map[supplierId] = _SupplierCost(
          name: name,
          productCount: 1,
          avgLeadTime: leadTime.toDouble(),
          totalMonthlySpend: spend,
        );
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => b.totalMonthlySpend.compareTo(a.totalMonthlySpend));
    return list;
  }

  /// Cash-flow projection for next 3 months (simplified: forecast × unitCost).
  List<double> _cashFlowProjection(AppState state) {
    // Base monthly projected spend from all products
    double baseSpend = 0;
    for (final p in state.products) {
      final rec =
          state.recommendations.where((r) => r.productId == p.id).firstOrNull;
      baseSpend += (rec?.forecastNextPeriod ?? 0) * p.unitCost;
    }
    // 3-month projection: month 1 = base, month 2 & 3 use same estimate
    return [baseSpend, baseSpend, baseSpend];
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final remaining = _remainingTasks(state);

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
              _buildGettingStartedTab(context, state, remaining),
              const _OwnerHelpTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardTab(BuildContext context, AppState state) {    final cogs = _monthlyCOGS(state);
    final holdingCost = _monthlyHoldingCost(state);
    final openOrderCost = _openOrderCost(state);
    final topProducts = _topExpenseProducts(state);
    final supplierCosts = _supplierCostBreakdown(state);
    final cashFlow = _cashFlowProjection(state);
    final totalSpend = topProducts.fold<double>(0, (s, p) => s + p.monthlySpend);

    final user = state.currentUser;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Shopify banner ───────────────────────────────────────────
          if (_showBanner && state.shopifyConnection?.isConnected != true)
            _buildShopifyBanner(),

          // ── Greeting ─────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$greeting, ${user?.name.split(' ').first ?? 'Owner'}',
                      style: AppTextStyles.h1),
                  Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                      style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
                ],
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => WelcomeTourDialog.show(context),
                icon: const Icon(Icons.play_circle_outline, size: 16),
                label: const Text('Replay tour'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Getting Started nudge banner (full checklist lives in the
          //    "Getting Started" tab now) ─────────────────────────────────
          if (_showChecklist) _buildOnboardingNudge(state),

          // ── Pending Actions (consolidated to-do) ─────────────────────
          _buildPendingActions(context, state),

          // ── Hero metric card ─────────────────────────────────────────
          _buildHeroCard(state, cogs, holdingCost, openOrderCost),

          const SizedBox(height: 24),

          // ── Operational + Manufacturing side by side ─────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              final pendingMaterialOrders = state.rawMaterialOrders
                  .where((o) => o.status != 'completed')
                  .length;
              final activeProductionOrders = state.productionOrders
                  .where((o) =>
                      o.status != ProductionOrderStatus.completed &&
                      o.status != ProductionOrderStatus.draft)
                  .length;
              final budgetRemaining =
                  state.latestCashFlow?.totalAvailable ?? 0;
              final allocatedBudget =
                  state.latestCashFlow?.allocatedToProduction ?? 0;

              final opPanel = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OPERATIONAL', style: AppTextStyles.eyebrow),
                  const SizedBox(height: 12),
                  _buildKPIGrid([
                    KPICard(
                      title: 'Total Units in Stock',
                      value: '${_totalUnits(state)}',
                      icon: Icons.inventory_2,
                      onTap: () => context.go('/products'),
                    ),
                    KPICard(
                      title: 'Items Below ROP',
                      value: '${state.lowStockItems}',
                      icon: Icons.warning_amber,
                      isAlert: state.lowStockItems > 0,
                      color: AppColors.warning,
                      onTap: () => context.go('/replenishment'),
                    ),
                    KPICard(
                      title: 'Open Recommendations',
                      value: '${state.openRecommendations}',
                      icon: Icons.assignment_late,
                      color: AppColors.primary,
                      onTap: () => context.go('/replenishment'),
                    ),
                    KPICard(
                      title: 'Forecast Accuracy',
                      value: state.forecastAccuracy > 0
                          ? '${(state.forecastAccuracy * 100).toStringAsFixed(1)}%'
                          : 'N/A',
                      icon: Icons.auto_graph,
                      color: AppColors.success,
                      onTap: () => context.go('/forecasts'),
                    ),
                  ]),
                ],
              );

              final mfgPanel = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MANUFACTURING', style: AppTextStyles.eyebrow),
                  const SizedBox(height: 12),
                  _buildKPIGrid([
                    KPICard(
                      title: 'Pending Material Orders',
                      value: '$pendingMaterialOrders',
                      icon: Icons.local_shipping,
                      isAlert: pendingMaterialOrders > 0,
                      color: AppColors.warning,
                      onTap: () => context.go('/orders/raw-materials'),
                    ),
                    KPICard(
                      title: 'Active Production Orders',
                      value: '$activeProductionOrders',
                      icon: Icons.precision_manufacturing,
                      color: AppColors.accent,
                      onTap: () => context.go('/production-orders'),
                    ),
                    KPICard(
                      title: 'Budget Remaining',
                      value:
                          'EGP ${(budgetRemaining - allocatedBudget).toStringAsFixed(0)}',
                      icon: Icons.account_balance,
                      isAlert: (budgetRemaining - allocatedBudget) < 0,
                      color: AppColors.success,
                    ),
                    KPICard(
                      title: 'Allocated to Production',
                      value: 'EGP ${allocatedBudget.toStringAsFixed(0)}',
                      icon: Icons.payments,
                      color: AppColors.primary,
                    ),
                  ]),
                ],
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: opPanel),
                    const SizedBox(width: 24),
                    Expanded(child: mfgPanel),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [opPanel, const SizedBox(height: 24), mfgPanel],
              );
            },
          ),

          const SizedBox(height: 24),

          // ── Charts Row ───────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 1000;
              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: isWide ? 3 : 0,
                    child: _buildCostBreakdownChart(
                        cogs, holdingCost, openOrderCost),
                  ),
                  SizedBox(width: isWide ? 24 : 0, height: isWide ? 0 : 24),
                  Expanded(
                    flex: isWide ? 2 : 0,
                    child: _buildCashFlowChart(cashFlow),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          // ── Demand vs Forecast ───────────────────────────────────────
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Demand vs Forecast (Last 6M)', style: AppTextStyles.h3),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 250,
                    child: _buildDemandForecastChart(state),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Top Expense Products Table ───────────────────────────────
          _ExpandableAnalyticsCard(
            title: 'Top Expense Products',
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('Monthly Forecast')),
                  DataColumn(label: Text('Unit Cost')),
                  DataColumn(label: Text('Monthly Spend')),
                  DataColumn(label: Text('% of Total')),
                ],
                rows: topProducts.take(10).map((p) {
                  final pct = totalSpend > 0
                      ? (p.monthlySpend / totalSpend * 100)
                      : 0.0;
                  return DataRow(cells: [
                    DataCell(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(p.name,
                            style: AppTextStyles.body
                                .copyWith(fontWeight: FontWeight.w600)),
                        Text(p.sku, style: AppTextStyles.label),
                      ],
                    )),
                    DataCell(Text('${p.monthlyForecast}')),
                    DataCell(Text('EGP ${p.unitCost.toStringAsFixed(2)}')),
                    DataCell(Text(
                        'EGP ${p.monthlySpend.toStringAsFixed(0)}')),
                    DataCell(Text('${pct.toStringAsFixed(1)}%')),
                  ]);
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Supplier Cost Breakdown ──────────────────────────────────
          _ExpandableAnalyticsCard(
            title: 'Supplier Cost Breakdown',
            child: HorizontallyScrollableTable(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Supplier')),
                  DataColumn(label: Text('# Products')),
                  DataColumn(label: Text('Avg Lead Time')),
                  DataColumn(label: Text('Monthly Spend')),
                ],
                rows: supplierCosts.map((s) {
                  return DataRow(cells: [
                    DataCell(Text(s.name,
                        style: AppTextStyles.body
                            .copyWith(fontWeight: FontWeight.w600))),
                    DataCell(Text('${s.productCount}')),
                    DataCell(Text(
                        '${s.avgLeadTime.toStringAsFixed(0)} days')),
                    DataCell(Text(
                        'EGP ${s.totalMonthlySpend.toStringAsFixed(0)}')),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-widgets ──────────────────────────────────────────────────────────

  // Note: the old critical-stock banner and "open recommendations" card were
  // removed — both are now consolidated into the Pending Actions card, which
  // routes to the Reorder Plan where the user reviews each SKU and decides
  // single vs bulk approve there. This keeps the dashboard quiet and avoids
  // accidental bulk orders triggered from a single click.

  Widget _buildShopifyBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.store, color: AppColors.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Connect your Shopify store', style: AppTextStyles.h3),
                Text('Sync products and inventory in real-time.',
                    style: AppTextStyles.body),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => context.go('/integrations'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Connect Store'),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _showBanner = false),
          ),
        ],
      ),
    );
  }

  Widget _buildOnboardingChecklist(AppState state) {
    // Whether the user has indicated they manufacture anything. We treat the
    // presence of *any* manufacturer / raw material / manufactured product as
    // the signal — for purely retail SMEs the manufacturing steps stay
    // optional and don't block setup completion.
    final hasManufacturing = state.manufacturers.isNotEmpty ||
        state.rawMaterials.isNotEmpty ||
        state.products.any(
            (p) => p.manufacturerId != null && p.manufacturerId!.isNotEmpty);

    final missingCost = state.productsMissingCost.length;
    final missingBom = state.manufacturedProductsMissingBom.length;
    final missingSupplier = state.productsMissingSupplier.length;

    // STRICT ORDER: partners first, then storage, then products. This matches
    // the data dependencies — products link to suppliers/manufacturers, BOMs
    // link to raw materials, and reorder plans need warehouses to make sense.
    final steps = <_ChecklistStep>[
      _ChecklistStep(
        label: '1. Add at least one supplier',
        route: '/suppliers',
        isDone: state.suppliers.isNotEmpty,
      ),
      if (hasManufacturing || state.products.isEmpty)
        _ChecklistStep(
          label: '2. Add manufacturers (skip if you only resell)',
          route: '/manufacturers',
          isDone: state.manufacturers.isNotEmpty || !hasManufacturing,
        ),
      if (hasManufacturing || state.products.isEmpty)
        _ChecklistStep(
          label: '3. Add raw materials & link them to suppliers',
          route: '/raw-materials',
          isDone: state.rawMaterials.isNotEmpty || !hasManufacturing,
        ),
      _ChecklistStep(
        label: '4. Add at least one warehouse',
        route: '/warehouses',
        isDone: state.warehouses.isNotEmpty,
      ),
      _ChecklistStep(
        label: '5. Add products (Shopify import or manual)',
        route: '/products',
        isDone: state.products.isNotEmpty,
      ),
      _ChecklistStep(
        label: missingCost == 0
            ? '6. Unit cost set for every product'
            : '6. Set unit cost for $missingCost product${missingCost == 1 ? '' : 's'}',
        route: '/products',
        isDone: state.products.isNotEmpty && missingCost == 0,
      ),
      _ChecklistStep(
        label: missingSupplier == 0
            ? '7. Every product is linked to a supplier'
            : '7. Link $missingSupplier product${missingSupplier == 1 ? '' : 's'} to a supplier',
        route: '/products',
        isDone: state.products.isNotEmpty && missingSupplier == 0,
      ),
      if (hasManufacturing)
        _ChecklistStep(
          label: missingBom == 0
              ? '8. BOM built for every manufactured product'
              : '8. Build BOM for $missingBom manufactured product${missingBom == 1 ? '' : 's'}',
          route: '/bom',
          isDone: missingBom == 0,
        ),
      _ChecklistStep(
        label: 'Import demand data (or wait for Shopify sales sync)',
        route: '/demand-data',
        isDone: state.demandByProduct.isNotEmpty,
      ),
      _ChecklistStep(
        label: 'Run your first reorder plan',
        route: '/forecasts',
        isDone: state.currentForecast != null,
      ),
      _ChecklistStep(
        label: 'Configure EOQ & holding cost in Settings',
        route: '/settings',
        isDone: state.settings.orderingCost != 250.0 ||
            state.settings.holdingRate != 0.20,
      ),
    ];
    final doneCount = steps.where((s) => s.isDone).length;
    final allDone = doneCount == steps.length;

    // Auto-hide if everything is done
    if (allDone) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.05),
            AppColors.secondary,
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
              const Icon(Icons.rocket_launch_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Get started — $doneCount of ${steps.length} complete',
                  style: AppTextStyles.h3.copyWith(color: AppColors.primary)),
              const Spacer(),
              // Progress bar
              SizedBox(
                width: 80,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: doneCount / steps.length,
                    minHeight: 6,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setState(() => _showChecklist = false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: steps
                .map((s) => _buildChecklistStep(context, s))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistStep(BuildContext context, _ChecklistStep step) {
    return InkWell(
      onTap: step.isDone ? null : () => context.go(step.route),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: step.isDone
              ? AppColors.success.withValues(alpha: 0.1)
              : Colors.white,
          border: Border.all(
            color: step.isDone
                ? AppColors.success.withValues(alpha: 0.4)
                : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              step.isDone
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 16,
              color: step.isDone
                  ? AppColors.success
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              step.label,
              style: AppTextStyles.bodySmall.copyWith(
                color: step.isDone
                    ? AppColors.success
                    : AppColors.textPrimary,
                decoration:
                    step.isDone ? TextDecoration.lineThrough : null,
                fontWeight: step.isDone ? FontWeight.normal : FontWeight.w500,
              ),
            ),
            if (!step.isDone) ...[
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_ios,
                  size: 10, color: AppColors.primary),
            ],
          ],
        ),
      ),
    );
  }

  // ── Hero card ────────────────────────────────────────────────────────────

  Widget _buildHeroCard(
      AppState state, double cogs, double holdingCost, double openOrderCost) {
    final accuracy = state.forecastAccuracy > 0
        ? '${(state.forecastAccuracy * 100).toStringAsFixed(1)}%'
        : '—';
    final nf = NumberFormat.decimalPattern();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1A2E),
            Color(0xFF24243E),
          ],
        ),
        borderRadius: AppRadius.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.inventory_2_rounded,
                    size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(
                'Inventory Cost',
                style: AppTextStyles.eyebrow.copyWith(
                  color: Colors.white.withValues(alpha: 0.55),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message:
                    'Cost basis — what you paid for the stock you currently hold '
                    '(Σ qty × unit cost). Distinct from retail value below.',
                child: Icon(
                  Icons.info_outline,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
              // Setup-health pill — surfaces the silent killer of KPI trust:
              // products with no unit cost. Clicking jumps straight to the
              // Products screen so the fix is one tap away.
              if (state.productsMissingCost.isNotEmpty) ...[
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => context.go('/products'),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 12, color: AppColors.warning),
                        const SizedBox(width: 6),
                        Text(
                          '${state.productsMissingCost.length} need cost',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'EGP',
                style: AppTextStyles.metricSuffix.copyWith(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                nf.format(state.totalStockValue.round()),
                style: AppTextStyles.metricXl.copyWith(color: Colors.white),
              ),
              const SizedBox(width: 14),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${state.products.length} products · ${nf.format(_totalUnits(state))} units',
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Divider(
              color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 18),
          IntrinsicHeight(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _heroSubMetric(
                    'Retail Value',
                    'EGP ${nf.format(state.totalRetailValue.round())}',
                    helper: 'Σ qty × selling price',
                    accent: AppColors.primary,
                  ),
                  VerticalDivider(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 40),
                  _heroSubMetric(
                    'Margin Locked',
                    'EGP ${nf.format(state.unrealizedMargin.round())}',
                    helper: 'Retail − Cost',
                    accent: state.unrealizedMargin >= 0
                        ? AppColors.success
                        : AppColors.error,
                  ),
                  VerticalDivider(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 40),
                  _heroSubMetric('Monthly COGS',
                      'EGP ${nf.format(cogs.round())}'),
                  VerticalDivider(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 40),
                  _heroSubMetric('Holding Cost',
                      'EGP ${nf.format(holdingCost.round())}'),
                  VerticalDivider(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 40),
                  _heroSubMetric(
                    'Open Orders',
                    'EGP ${nf.format(openOrderCost.round())}',
                    isAlert: openOrderCost > 0,
                  ),
                  VerticalDivider(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 40),
                  _heroSubMetric('Forecast Acc.', accuracy),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroSubMetric(String label, String value,
      {bool isAlert = false, String? helper, Color? accent}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (accent != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label.toUpperCase(),
              style: AppTextStyles.eyebrow.copyWith(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 10,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: AppTextStyles.metricMd.copyWith(
            color: isAlert && !value.endsWith(' 0')
                ? AppColors.warning
                : (accent ?? Colors.white),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(
            helper,
            style: AppTextStyles.bodySmall.copyWith(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildKPIGrid(List<Widget> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w > 900 ? 4 : w > 500 ? 2 : 1;
        const spacing = 16.0;
        final cardW = (w - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map((c) => SizedBox(width: cardW, child: c))
              .toList(),
        );
      },
    );
  }

  Widget _buildCostBreakdownChart(
      double cogs, double holdingCost, double openOrderCost) {
    final total = cogs + holdingCost + openOrderCost;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monthly Cost Breakdown', style: AppTextStyles.h3),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: total == 0
                  ? const Center(child: Text('No cost data yet.'))
                  : PieChart(PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      sections: [
                        PieChartSectionData(
                          value: cogs,
                          title:
                              '${(cogs / total * 100).toStringAsFixed(0)}%',
                          color: AppColors.primary,
                          radius: 50,
                          titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                        PieChartSectionData(
                          value: holdingCost,
                          title:
                              '${(holdingCost / total * 100).toStringAsFixed(0)}%',
                          color: AppColors.warning,
                          radius: 50,
                          titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                        PieChartSectionData(
                          value: openOrderCost,
                          title:
                              '${(openOrderCost / total * 100).toStringAsFixed(0)}%',
                          color: AppColors.error,
                          radius: 50,
                          titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                      ],
                    )),
            ),
            const SizedBox(height: 12),
            _legendItem(AppColors.primary, 'COGS',
                'EGP ${cogs.toStringAsFixed(0)}'),
            _legendItem(AppColors.warning, 'Holding',
                'EGP ${holdingCost.toStringAsFixed(0)}'),
            _legendItem(AppColors.error, 'Open Orders',
                'EGP ${openOrderCost.toStringAsFixed(0)}'),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(width: 12, height: 12, color: color),
          const SizedBox(width: 8),
          Text(label, style: AppTextStyles.body),
          const Spacer(),
          Text(value,
              style:
                  AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildCashFlowChart(List<double> cashFlow) {
    final months = ['Month 1', 'Month 2', 'Month 3'];
    final maxY = cashFlow.isEmpty
        ? 100.0
        : cashFlow.reduce((a, b) => a > b ? a : b) * 1.2;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cash Flow Projection (3M)', style: AppTextStyles.h3),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= months.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(months[i],
                                style: AppTextStyles.label),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: cashFlow.asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value,
                          color: AppColors.accent,
                          width: 40,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Projected monthly inventory spend: EGP ${cashFlow.isNotEmpty ? cashFlow.first.toStringAsFixed(0) : 0}',
              style: AppTextStyles.label,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemandForecastChart(AppState state) {
    final forecast = state.currentForecast;
    if (forecast == null || forecast.periods.isEmpty) {
      final allDemand = state.demandByProduct.values.isNotEmpty
          ? state.demandByProduct.values.first
          : [];
      final spots = allDemand
          .asMap()
          .entries
          .take(6)
          .map((e) => FlSpot(e.key.toDouble(), e.value.quantity.toDouble()))
          .toList();

      return LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(
            rightTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: AppColors.border),
          ),
          lineBarsData: [
            if (spots.isNotEmpty)
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: AppColors.primary,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.primary.withValues(alpha: 0.1),
                ),
              ),
          ],
        ),
      );
    }

    final take = forecast.periods.length.clamp(0, 6);
    final actualSpots = forecast.actualDemand
        .take(take)
        .toList()
        .asMap()
        .entries
        .where((e) => e.value > 0)
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    final forecastSpots = forecast.forecast
        .take(take)
        .toList()
        .asMap()
        .entries
        .where((e) => e.value > 0)
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(
          rightTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: AppColors.border),
        ),
        lineBarsData: [
          if (actualSpots.isNotEmpty)
            LineChartBarData(
              spots: actualSpots,
              isCurved: true,
              color: AppColors.textSecondary,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primary.withValues(alpha: 0.05),
              ),
            ),
          if (forecastSpots.isNotEmpty)
            LineChartBarData(
              spots: forecastSpots,
              isCurved: true,
              color: AppColors.primary,
              barWidth: 3,
              dashArray: [5, 5],
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }

  // ── Pending Actions card ───────────────────────────────────────────────

  Widget _buildPendingActions(BuildContext context, AppState state) {
    final lowStockCount = state.criticalStockProducts.length;
    final draftPOs = state.purchaseOrders
        .where((po) => po.status == OrderStatus.draft)
        .length;
    final openRecs = state.openRecommendations;
    final draftProductions = state.productionOrders
        .where((p) => p.status == ProductionOrderStatus.draft)
        .length;
    final pendingMaterialOrders = state.rawMaterialOrders
        .where((o) => o.status != 'completed' && o.status != 'cancelled')
        .length;

    final actions = <PendingAction>[];
    if (lowStockCount > 0) {
      actions.add(PendingAction(
        icon: Icons.inventory_2_outlined,
        iconColor: AppColors.error,
        label:
            '$lowStockCount product${lowStockCount == 1 ? '' : 's'} need reordering — review in Reorder Plan',
        count: '$lowStockCount',
        onTap: () => context.go('/forecasts'),
      ));
    }
    if (openRecs > 0) {
      actions.add(PendingAction(
        icon: Icons.recommend_outlined,
        iconColor: AppColors.warning,
        label: 'Replenishment recommendations awaiting review',
        count: '$openRecs',
        onTap: () => context.go('/replenishment'),
      ));
    }
    if (draftPOs > 0) {
      actions.add(PendingAction(
        icon: Icons.description_outlined,
        iconColor: AppColors.info,
        label: 'Draft purchase orders to send',
        count: '$draftPOs',
        onTap: () => context.go('/orders'),
      ));
    }
    if (draftProductions > 0) {
      actions.add(PendingAction(
        icon: Icons.factory_outlined,
        iconColor: AppColors.primary,
        label: 'Production orders in draft',
        count: '$draftProductions',
        onTap: () => context.go('/production-orders'),
      ));
    }
    if (pendingMaterialOrders > 0) {
      actions.add(PendingAction(
        icon: Icons.local_shipping_outlined,
        iconColor: AppColors.info,
        label: 'Raw material orders in progress',
        count: '$pendingMaterialOrders',
        onTap: () => context.go('/raw-materials'),
      ));
    }

    if (actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: PendingActionsCard(actions: actions),
    );
  }

  // ── Getting Started tab ────────────────────────────────────────────────

  Widget _buildOnboardingNudge(AppState state) {
    final remaining = _remainingTasks(state);
    if (remaining == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.rocket_launch_outlined,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$remaining setup task${remaining == 1 ? '' : 's'} remaining to fully activate Ma5zony.',
              style: AppTextStyles.body.copyWith(color: AppColors.primary),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _selectedTab = 1),
            child: const Text('Open'),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: AppColors.textSecondary,
            onPressed: () => setState(() => _showChecklist = false),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildGettingStartedTab(
      BuildContext context, AppState state, int remaining) {
    final user = state.currentUser;
    final completed = 6 - remaining;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GettingStartedHeroCard(
            userName: user?.name.split(' ').first ?? 'Owner',
            emoji: '👋',
            subtitle:
                'Finish a few quick steps to get the most out of Ma5zony.',
            doneCount: completed,
            totalCount: 6,
          ),
          const SizedBox(height: 24),
          // Surface the existing checklist (keeps prior logic intact)
          _buildOnboardingChecklist(state),
          const SizedBox(height: 8),
          Text('Set up your business', style: AppTextStyles.h3),
          const SizedBox(height: 12),
          SetupActionCard(
            icon: Icons.shopping_bag_outlined,
            iconColor: const Color(0xFF95BF47),
            title: 'Connect your Shopify store',
            subtitle:
                'Sync products, inventory and orders automatically with Ma5zony.',
            ctaLabel: state.shopifyConnection?.isConnected == true
                ? 'Connected'
                : 'Connect',
            onTap: () => context.go('/integrations'),
          ),
          const SizedBox(height: 12),
          SetupActionCard(
            icon: Icons.group_outlined,
            iconColor: AppColors.primary,
            title: 'Invite your team',
            subtitle:
                'Add managers, manufacturers and suppliers so they can collaborate.',
            ctaLabel: 'Manage',
            onTap: () => context.go('/settings'),
          ),
          const SizedBox(height: 12),
          SetupActionCard(
            icon: Icons.settings_outlined,
            iconColor: AppColors.warning,
            title: 'Configure workspace settings',
            subtitle:
                'Set EOQ, holding cost, currency and other business preferences.',
            ctaLabel: 'Configure',
            onTap: () => context.go('/settings'),
          ),
          const SizedBox(height: 24),
          HelpSupportCard(onTap: () => setState(() => _selectedTab = 2)),
        ],
      ),
    );
  }
}

// ── Data classes ────────────────────────────────────────────────────────────

class _ProductSpend {
  final String name;
  final String sku;
  final int monthlyForecast;
  final double unitCost;
  final double monthlySpend;

  _ProductSpend({
    required this.name,
    required this.sku,
    required this.monthlyForecast,
    required this.unitCost,
    required this.monthlySpend,
  });
}

class _SupplierCost {
  final String name;
  final int productCount;
  final double avgLeadTime;
  final double totalMonthlySpend;

  _SupplierCost({
    required this.name,
    required this.productCount,
    required this.avgLeadTime,
    required this.totalMonthlySpend,
  });
}

class _ChecklistStep {
  final String label;
  final String route;
  final bool isDone;

  _ChecklistStep({
    required this.label,
    required this.route,
    required this.isDone,
  });
}

// ── Help & Support tab ──────────────────────────────────────────────────────

/// A collapsible Card widget for heavy analytics sections on the dashboard.
/// Starts collapsed so it doesn't dominate the initial view.
class _ExpandableAnalyticsCard extends StatefulWidget {
  final String title;
  final Widget child;
  const _ExpandableAnalyticsCard({required this.title, required this.child});

  @override
  State<_ExpandableAnalyticsCard> createState() =>
      _ExpandableAnalyticsCardState();
}

class _ExpandableAnalyticsCardState extends State<_ExpandableAnalyticsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Text(widget.title, style: AppTextStyles.h3),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textSubdued,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

class _OwnerHelpTab extends StatelessWidget {
  const _OwnerHelpTab();

  @override
  Widget build(BuildContext context) {
    final topics = const [
      _HelpTopic(Icons.inventory_2_outlined, 'Products & Inventory',
          'Manage SKUs, stock levels and warehouses.'),
      _HelpTopic(Icons.account_tree_outlined, 'Bill of Materials',
          'Define BOMs and link raw materials to finished goods.'),
      _HelpTopic(Icons.show_chart, 'Demand Forecasting',
          'Run SMA / SES forecasts on your sales history.'),
      _HelpTopic(Icons.shopping_cart_outlined, 'Purchase Orders',
          'Approve replenishments and track POs to suppliers.'),
      _HelpTopic(Icons.shopping_bag_outlined, 'Shopify Integration',
          'Connect your store, sync products and import orders.'),
      _HelpTopic(Icons.factory_outlined, 'Manufacturing',
          'Production orders, manufacturers and raw material flow.'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Help & Support', style: AppTextStyles.h2),
          const SizedBox(height: 4),
          Text(
            'Browse guides, contact support or learn how to get the most out of Ma5zony.',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          HelpSupportCard(onTap: () {}),
          const SizedBox(height: 24),
          Text('Browse topics', style: AppTextStyles.h3),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final cols = w > 1000 ? 3 : (w > 600 ? 2 : 1);
              final gap = 12.0;
              final cardW = (w - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: topics
                    .map((t) => SizedBox(
                          width: cardW,
                          child: _HelpTopicCard(topic: t),
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'Ma5zony • v1.0',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpTopic {
  final IconData icon;
  final String title;
  final String subtitle;
  const _HelpTopic(this.icon, this.title, this.subtitle);
}

class _HelpTopicCard extends StatelessWidget {
  final _HelpTopic topic;
  const _HelpTopicCard({required this.topic});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(topic.icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(topic.title,
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(topic.subtitle,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
