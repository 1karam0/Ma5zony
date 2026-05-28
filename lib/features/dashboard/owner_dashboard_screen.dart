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
/// Supply-chain & inventory focused: stock health, reorder alerts, forecast
/// accuracy, demand vs forecast chart, and onboarding progress. No financial
/// breakdowns (COGS / holding cost / cash flow) — Ma5zony is an inventory
/// management system, not an accounting tool.
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

  /// Single source of truth for the Getting Started checklist.
  /// Exactly 6 top-level steps — no sub-tasks. Detailed nudges (missing unit
  /// cost, unlinked products, missing BOMs, etc.) live on their dedicated
  /// pages so this checklist stays calm and scannable.
  List<_ChecklistStep> _setupSteps(AppState state) {
    return [
      _ChecklistStep(
        label: 'Add at least one supplier',
        route: '/suppliers',
        isDone: state.suppliers.isNotEmpty,
      ),
      _ChecklistStep(
        label: 'Add at least one warehouse',
        route: '/warehouses',
        isDone: state.warehouses.isNotEmpty,
      ),
      _ChecklistStep(
        label: 'Add your products (Shopify import or manual)',
        route: '/products',
        isDone: state.products.isNotEmpty,
      ),
      _ChecklistStep(
        label: 'Import sales / demand data',
        route: '/demand-data',
        isDone: state.demandByProduct.isNotEmpty,
      ),
      _ChecklistStep(
        label: 'Run your first reorder plan',
        route: '/forecasts',
        isDone: state.currentForecast != null,
      ),
      _ChecklistStep(
        label: 'Review reorder settings (lead-time buffer, safety stock)',
        route: '/settings',
        isDone: state.settings.orderingCost != 250.0 ||
            state.settings.holdingRate != 0.20,
      ),
    ];
  }

  /// Remaining onboarding tasks count (drives the tab badge + hero progress).
  int _remainingTasks(AppState state) =>
      _setupSteps(state).where((s) => !s.isDone).length;

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Total units in stock.
  int _totalUnits(AppState state) =>
      state.products.fold<int>(0, (s, p) => s + p.currentStock);

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

  Widget _buildDashboardTab(BuildContext context, AppState state) {
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

          // ── Getting Started nudge banner ─────────────────────────────
          if (_showChecklist) _buildOnboardingNudge(state),

          // ── Pending Actions (consolidated to-do) ─────────────────────
          _buildPendingActions(context, state),

          // ── Inventory snapshot hero ──────────────────────────────────
          _buildHeroCard(state),

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
              final completedProductions = state.productionOrders
                  .where((o) => o.status == ProductionOrderStatus.completed)
                  .length;

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
                      title: 'Completed Productions',
                      value: '$completedProductions',
                      icon: Icons.check_circle_outline,
                      color: AppColors.success,
                      onTap: () => context.go('/production-orders'),
                    ),
                    KPICard(
                      title: 'Raw Materials Tracked',
                      value: '${state.rawMaterials.length}',
                      icon: Icons.category_outlined,
                      color: AppColors.primary,
                      onTap: () => context.go('/raw-materials'),
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
    final steps = _setupSteps(state);
    final doneCount = steps.where((s) => s.isDone).length;
    final allDone = doneCount == steps.length;

    // Auto-hide if everything is done
    if (allDone) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — title + progress
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.rocket_launch_outlined,
                    size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Setup checklist', style: AppTextStyles.h3),
                    const SizedBox(height: 2),
                    Text(
                      '$doneCount of ${steps.length} complete · finish to unlock forecasting',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 90,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: doneCount / steps.length,
                    minHeight: 6,
                    backgroundColor:
                        AppColors.primary.withValues(alpha: 0.15),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary),
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
                tooltip: 'Hide checklist',
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Steps — clean vertical list, each numbered
          ...List.generate(steps.length, (i) {
            final step = steps[i];
            return _buildChecklistStep(context, step, i + 1);
          }),
        ],
      ),
    );
  }

  Widget _buildChecklistStep(
      BuildContext context, _ChecklistStep step, int number) {
    return InkWell(
      onTap: step.isDone ? null : () => context.go(step.route),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // Numbered circle or checkmark
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: step.isDone
                    ? AppColors.success
                    : AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: step.isDone
                    ? null
                    : Border.all(
                        color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: step.isDone
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text(
                      '$number',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                step.label,
                style: AppTextStyles.body.copyWith(
                  color: step.isDone
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  decoration:
                      step.isDone ? TextDecoration.lineThrough : null,
                  fontWeight:
                      step.isDone ? FontWeight.normal : FontWeight.w500,
                ),
              ),
            ),
            if (!step.isDone)
              const Icon(Icons.arrow_forward_ios,
                  size: 12, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  // ── Hero card ────────────────────────────────────────────────────────────

  Widget _buildHeroCard(AppState state) {
    final accuracy = state.forecastAccuracy > 0
        ? '${(state.forecastAccuracy * 100).toStringAsFixed(1)}%'
        : '—';
    final nf = NumberFormat.decimalPattern();
    final lowStock = state.lowStockItems;

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
                'Inventory Snapshot',
                style: AppTextStyles.eyebrow.copyWith(
                  color: Colors.white.withValues(alpha: 0.55),
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                nf.format(_totalUnits(state)),
                style: AppTextStyles.metricXl.copyWith(color: Colors.white),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'units on hand',
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'across ${state.products.length} products · ${state.warehouses.length} warehouse${state.warehouses.length == 1 ? '' : 's'}',
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 18),
          IntrinsicHeight(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _heroSubMetric(
                    'Items Below ROP',
                    '$lowStock',
                    helper: lowStock > 0
                        ? 'Need reordering'
                        : 'All healthy',
                    accent: lowStock > 0
                        ? AppColors.warning
                        : AppColors.success,
                    isAlert: lowStock > 0,
                  ),
                  VerticalDivider(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 40),
                  _heroSubMetric(
                    'Open Recommendations',
                    '${state.openRecommendations}',
                    helper: 'Awaiting review',
                    accent: AppColors.primary,
                  ),
                  VerticalDivider(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 40),
                  _heroSubMetric(
                    'Active Suppliers',
                    '${state.suppliers.length}',
                    helper: 'In your network',
                  ),
                  VerticalDivider(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 40),
                  _heroSubMetric(
                    'Forecast Accuracy',
                    accuracy,
                    helper: state.forecastAccuracy > 0
                        ? 'Last forecast run'
                        : 'Run a forecast first',
                    accent: AppColors.success,
                  ),
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
    final steps = _setupSteps(state);
    final total = steps.length;
    final completed = total - remaining;
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
            totalCount: total,
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
                'Tune reorder rules, safety stock and other inventory preferences.',
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
