import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:ma5zony/features/products/products_screen.dart'
    show showProductEditDialog;
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/replenishment_recommendation.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';

/// Reorder Plan — owner picks two business knobs (no algorithm jargon):
///   • Order coverage  — how many days this order should last.
///   • Sales window    — how many days of history to base the average on.
/// Quantity, urgency, and the momentum arrow are derived live.
class ReorderPlanScreen extends StatefulWidget {
  const ReorderPlanScreen({super.key});

  @override
  State<ReorderPlanScreen> createState() => _ReorderPlanScreenState();
}

class _ReorderPlanScreenState extends State<ReorderPlanScreen> {
  final Set<String> _selected = <String>{};
  bool _busy = false;

  int _coverageDays = 45;
  int _salesWindowDays = 90;

  static const _kCoverageOptions = [14, 30, 45, 60, 90];
  static const _kWindowOptions = [30, 60, 90, 180];

  // ── Helpers ─────────────────────────────────────────────────────────────

  double _avgDaily(AppState state, String productId) {
    final records = state.demandByProduct[productId] ?? const [];
    if (records.isEmpty) return 0;
    final cutoff =
        DateTime.now().subtract(Duration(days: _salesWindowDays));
    final inWindow =
        records.where((r) => r.periodStart.isAfter(cutoff)).toList();
    if (inWindow.isEmpty) return 0;
    final total = inWindow.fold<int>(0, (s, r) => s + r.quantity);
    return total / _salesWindowDays;
  }

  /// Recent-half rate vs older-half rate of the sales window.
  /// Returns the % delta (e.g. 0.23 = +23%). 0 if no signal.
  double _momentumPct(AppState state, String productId) {
    final records = state.demandByProduct[productId] ?? const [];
    if (records.isEmpty) return 0;
    final now = DateTime.now();
    final half = (_salesWindowDays / 2).round();
    final midCutoff = now.subtract(Duration(days: half));
    final startCutoff = now.subtract(Duration(days: _salesWindowDays));
    final recent = records
        .where((r) => r.periodStart.isAfter(midCutoff))
        .fold<int>(0, (s, r) => s + r.quantity);
    final older = records
        .where((r) =>
            r.periodStart.isAfter(startCutoff) &&
            !r.periodStart.isAfter(midCutoff))
        .fold<int>(0, (s, r) => s + r.quantity);
    if (older == 0) return recent > 0 ? 1.0 : 0.0;
    return (recent - older) / older;
  }

  ReplenishmentRecommendation _buildRec(Product p, double avgDaily) {
    final needed = (avgDaily * _coverageDays).ceil();
    final qty = math.max(0, needed - p.currentStock);
    final leadDays = p.leadTimeDays > 0 ? p.leadTimeDays : 14;
    final leadTimeConsumption = (avgDaily * leadDays).ceil();
    DateTime orderDate;
    if (p.currentStock <= leadTimeConsumption || avgDaily <= 0) {
      orderDate = DateTime.now();
    } else {
      final slackDays =
          ((p.currentStock - leadTimeConsumption) / avgDaily).floor();
      orderDate = DateTime.now().add(Duration(days: slackDays));
    }
    final urgency = p.currentStock == 0
        ? 'Critical'
        : (qty > 0 ? 'Warning' : 'Normal');
    return ReplenishmentRecommendation(
      productId: p.id,
      productName: p.name,
      sku: p.sku,
      currentStock: p.currentStock,
      forecastNextPeriod: (avgDaily * 30).round(),
      reorderPoint: leadTimeConsumption,
      suggestedOrderQty: qty,
      recommendedOrderDate: orderDate,
      urgency: urgency,
    );
  }

  String _recipientFor(Product p, AppState state) {
    if (p.manufacturerId != null && p.manufacturerId!.isNotEmpty) {
      final m = state.manufacturers
          .where((x) => x.id == p.manufacturerId)
          .firstOrNull;
      return m?.name ?? 'Unassigned manufacturer';
    }
    if (p.supplierId != null && p.supplierId!.isNotEmpty) {
      final s = state.suppliers
          .where((x) => x.id == p.supplierId)
          .firstOrNull;
      return s?.name ?? 'Unassigned supplier';
    }
    return 'No supplier / manufacturer set';
  }

  bool _isManufactured(Product p) =>
      p.manufacturerId != null && p.manufacturerId!.isNotEmpty;

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _approveSingle(
      ReplenishmentRecommendation rec, Product product) async {
    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<AppState>();
    setState(() => _busy = true);
    try {
      if (_isManufactured(product)) {
        await state.approveReplenishmentManufacture(rec);
        messenger.showSnackBar(SnackBar(
          content: Text(
              'Production order created for ${product.name} (${rec.suggestedOrderQty} units)'),
          backgroundColor: AppColors.success,
        ));
      } else {
        await state.approveRecommendation(rec);
        messenger.showSnackBar(SnackBar(
          content: Text(
              'Purchase order created for ${product.name} (${rec.suggestedOrderQty} units)'),
          backgroundColor: AppColors.success,
        ));
      }
      setState(() => _selected.remove(product.id));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Could not create order: ${e.toString().replaceAll('Exception: ', '')}'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveBulk(List<_PlanRow> rows) async {
    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<AppState>();

    final selectedRows = rows
        .where((r) => _selected.contains(r.product.id) &&
            (r.rec.suggestedOrderQty > 0 || r.product.currentStock == 0))
        .toList();

    if (selectedRows.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Select one or more low-stock products to bulk-order.'),
      ));
      return;
    }

    setState(() => _busy = true);
    int successCount = 0;
    final failures = <String>[];

    try {
      for (final row in selectedRows) {
        try {
          if (_isManufactured(row.product)) {
            await state.approveReplenishmentManufacture(row.rec);
          } else {
            await state.approveRecommendation(row.rec);
          }
          successCount++;
        } catch (e) {
          failures.add('${row.product.name}: ${e.toString().replaceAll('Exception: ', '')}');
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _selected.clear();
        });
      }
    }

    if (!mounted) return;
    if (failures.isEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text('Bulk order created — $successCount order(s) sent.'),
        backgroundColor: AppColors.success,
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(
            '$successCount order(s) created, ${failures.length} failed.\nFirst error: ${failures.first}'),
        backgroundColor: AppColors.warning,
        duration: const Duration(seconds: 8),
      ));
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final products = state.products; // active only

    // Build one display row per product using the user-chosen windows.
    // Then keep ONLY products that are genuinely low on stock — i.e. the
    // current stock can't cover the lead time at the recent sales rate.
    // Products with no sales history at all are excluded (we can't make
    // a recommendation without a signal).
    final allRows = <_PlanRow>[];
    for (final p in products) {
      final avgDaily = _avgDaily(state, p.id);
      final rec = _buildRec(p, avgDaily);
      final momentum = _momentumPct(state, p.id);
      allRows.add(_PlanRow(
        product: p,
        rec: rec,
        avgMonthly: avgDaily * 30,
        momentum: momentum,
      ));
    }

    // Low-stock filter: needs a new order based on sales × lead time, OR
    // is completely out of stock (regardless of whether we have sales history).
    final rows = allRows
        .where((r) => r.rec.suggestedOrderQty > 0 || r.product.currentStock == 0)
        .toList();

    // Sort: critical (stock 0) first; ties by stock ascending.
    rows.sort((a, b) {
      final aCrit = a.rec.currentStock == 0 ? 0 : 1;
      final bCrit = b.rec.currentStock == 0 ? 0 : 1;
      final cmp = aCrit.compareTo(bCrit);
      if (cmp != 0) return cmp;
      return a.rec.currentStock.compareTo(b.rec.currentStock);
    });

    final actionableCount = rows.length;
    final hiddenHealthyCount = allRows.length - rows.length;
    final selectedActionable = rows
        .where((r) =>
            _selected.contains(r.product.id) &&
            (r.rec.suggestedOrderQty > 0 || r.product.currentStock == 0))
        .length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reorder Plan', style: AppTextStyles.h1),
                      const SizedBox(height: 4),
                      Text(
                        actionableCount == 0
                            ? (hiddenHealthyCount > 0
                                ? 'All $hiddenHealthyCount product${hiddenHealthyCount == 1 ? '' : 's'} can cover their lead time at the current sales rate. Nothing to reorder right now.'
                                : 'You\'re all stocked up. Nothing needs reordering right now.')
                            : '$actionableCount product${actionableCount == 1 ? '' : 's'} can\'t cover the lead time at the recent sales rate. Tick the ones you want and create a bulk order, or approve them one by one.',
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                _SyncButton(busy: _busy),
              ],
            ),
            const SizedBox(height: 20),

            // ── Data-quality banner (Phase 1.3) ────────────────────────
            // The reorder math only works if upstream data is sound. List
            // products whose effective cost will be 0 / wrong so the user
            // can fix them before trusting any number on this screen.
            _DataQualityBanner(state: state, products: products),

            // ── Window pickers ──────────────────────────────────
            _WindowPickers(
              coverageDays: _coverageDays,
              coverageOptions: _kCoverageOptions,
              salesWindowDays: _salesWindowDays,
              windowOptions: _kWindowOptions,
              onCoverageChanged: (v) => setState(() => _coverageDays = v),
              onWindowChanged: (v) => setState(() => _salesWindowDays = v),
            ),
            const SizedBox(height: 16),

            // ── Bulk action bar ────────────────────────────────────────
            _BulkActionBar(
              selectedCount: selectedActionable,
              busy: _busy,
              onClear: () => setState(_selected.clear),
              onSelectAllLow: () {
                setState(() {
                  _selected
                    ..clear()
                    ..addAll(rows
                        .where((r) => r.rec.suggestedOrderQty > 0)
                        .map((r) => r.product.id));
                });
              },
              onCreateBulk: () => _approveBulk(rows),
            ),
            const SizedBox(height: 16),

            // ── Plan table ─────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: rows.isEmpty
                  ? _EmptyState(
                      hiddenHealthyCount: hiddenHealthyCount,
                      totalProducts: allRows.length,
                    )
                  : LayoutBuilder(builder: (ctx, constraints) {
                      // Table is dense — give it a comfortable minimum
                      // width and let it scroll horizontally on narrow
                      // viewports instead of squishing the cells (which
                      // caused pixel overflows in the columns).
                      const minTableWidth = 980.0;
                      final tableWidth = math.max(
                          constraints.maxWidth, minTableWidth);
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: tableWidth,
                          child: Column(
                            children: [
                              _TableHeader(),
                              for (int i = 0; i < rows.length; i++)
                                _PlanRowTile(
                                  row: rows[i],
                                  isLast: i == rows.length - 1,
                                  selected:
                                      _selected.contains(rows[i].product.id),
                                  busy: _busy,
                                  isManufactured:
                                      _isManufactured(rows[i].product),
                                  recipient: _recipientFor(
                                      rows[i].product, state),
                                  onSelected: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selected.add(rows[i].product.id);
                                      } else {
                                        _selected.remove(rows[i].product.id);
                                      }
                                    });
                                  },
                                  onApprove: () => _approveSingle(
                                      rows[i].rec, rows[i].product),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
            ),
            const SizedBox(height: 24),

            // ── Footnote ───────────────────────────────────────────────
            Text(
              'Showing only products whose current stock can\'t cover the lead time at the recent sales rate. '
              'Order qty = (avg daily sales over last $_salesWindowDays days) × $_coverageDays − current stock. '
              'Momentum compares the recent half of the window to the older half.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSubdued),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Models ──────────────────────────────────────────────────────────────────

class _PlanRow {
  final Product product;
  final ReplenishmentRecommendation rec;
  final double avgMonthly;
  final double momentum; // +0.23 = +23% vs older half of window
  _PlanRow({
    required this.product,
    required this.rec,
    required this.avgMonthly,
    required this.momentum,
  });
}

// ── Header / Bulk Bar / Row / Empty ─────────────────────────────────────────

class _SyncButton extends StatelessWidget {
  final bool busy;
  const _SyncButton({required this.busy});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final syncing = state.shopifySyncInProgress;
    final lastSync = state.lastShopifySyncAt;
    final connected = state.shopifyConnection?.isConnected ?? false;
    if (!connected) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: (busy || syncing)
              ? null
              : () => context.read<AppState>().syncShopifyNow(),
          icon: syncing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 16),
          label: Text(syncing ? 'Syncing…' : 'Sync sales'),
        ),
        if (lastSync != null) ...[
          const SizedBox(height: 4),
          Text(
            'Last sync: ${_relative(lastSync)}',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSubdued, fontSize: 11),
          ),
        ],
      ],
    );
  }

  String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _BulkActionBar extends StatelessWidget {
  final int selectedCount;
  final bool busy;
  final VoidCallback onClear;
  final VoidCallback onSelectAllLow;
  final VoidCallback onCreateBulk;

  const _BulkActionBar({
    required this.selectedCount,
    required this.busy,
    required this.onClear,
    required this.onSelectAllLow,
    required this.onCreateBulk,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedCount > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: hasSelection ? AppColors.primaryLight : AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasSelection ? AppColors.primary : AppColors.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasSelection
                ? Icons.check_circle
                : Icons.checklist_rtl_outlined,
            color: hasSelection ? AppColors.primary : AppColors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasSelection
                  ? '$selectedCount product${selectedCount == 1 ? '' : 's'} selected for bulk order'
                  : 'Tip: tick several products and create one bulk order — they\'re grouped per supplier / manufacturer automatically.',
              style: AppTextStyles.body.copyWith(
                color: hasSelection
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontWeight: hasSelection ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (hasSelection)
            TextButton(onPressed: busy ? null : onClear, child: const Text('Clear')),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: busy ? null : onSelectAllLow,
            icon: const Icon(Icons.done_all, size: 16),
            label: const Text('Select all low-stock'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: (busy || !hasSelection) ? null : onCreateBulk,
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Create Bulk Order'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.tableHeader;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 40), // checkbox column
          Expanded(flex: 4, child: Text('PRODUCT', style: style)),
          Expanded(flex: 2, child: Text('STOCK', style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text('SALES / MO', style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text('ORDER QTY', style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text('ORDER BY', style: style)),
          Expanded(flex: 3, child: Text('SEND TO', style: style)),
          const SizedBox(width: 130), // approve button
        ],
      ),
    );
  }
}

class _PlanRowTile extends StatelessWidget {
  final _PlanRow row;
  final bool isLast;
  final bool selected;
  final bool busy;
  final bool isManufactured;
  final String recipient;
  final ValueChanged<bool?> onSelected;
  final VoidCallback onApprove;

  const _PlanRowTile({
    required this.row,
    required this.isLast,
    required this.selected,
    required this.busy,
    required this.isManufactured,
    required this.recipient,
    required this.onSelected,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final p = row.product;
    final rec = row.rec;
    final needsOrder = rec.suggestedOrderQty > 0;
    final critical = p.currentStock == 0;
    final noRecipient = recipient.startsWith('No ') || recipient.startsWith('Unassigned');
    final noCost = p.unitCost == 0;

    Color stockColor;
    if (critical) {
      stockColor = AppColors.error;
    } else if (needsOrder) {
      stockColor = AppColors.warning;
    } else {
      stockColor = AppColors.textPrimary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryLight.withValues(alpha: 0.3) : null,
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            child: Checkbox(
              value: selected,
              onChanged: (needsOrder || critical) ? onSelected : null,
            ),
          ),
          // Product
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isManufactured
                          ? Icons.precision_manufacturing_outlined
                          : Icons.local_shipping_outlined,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.tableCell
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                Text(
                  p.sku,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
                if (noCost) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 12, color: AppColors.warning),
                      const SizedBox(width: 4),
                      Text('Set unit cost',
                          style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.warning, fontSize: 11)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Stock
          Expanded(
            flex: 2,
            child: Builder(builder: (ctx) {
              // Multi-location: show per-warehouse breakdown as small chips
              // below the total when the product has per-location data.
              final wh = p.stockByWarehouse;
              if (wh.isEmpty) {
                return Text(
                  '${p.currentStock}',
                  textAlign: TextAlign.right,
                  style: AppTextStyles.tableNum.copyWith(
                    color: stockColor,
                    fontWeight: critical ? FontWeight.w700 : FontWeight.w600,
                  ),
                );
              }
              final warehouses = ctx.read<AppState>().warehouses;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${p.currentStock}',
                    textAlign: TextAlign.right,
                    style: AppTextStyles.tableNum.copyWith(
                      color: stockColor,
                      fontWeight: critical ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  ...wh.entries.map((e) {
                    final name = warehouses
                            .where((w) => w.id == e.key)
                            .firstOrNull
                            ?.name ??
                        e.key;
                    return Text(
                      '$name: ${e.value}',
                      style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 10,
                          color: AppColors.textSecondary),
                      textAlign: TextAlign.right,
                    );
                  }),
                ],
              );
            }),
          ),
          // Avg sales / mo + momentum
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  row.avgMonthly == 0
                      ? '—'
                      : row.avgMonthly.toStringAsFixed(1),
                  textAlign: TextAlign.right,
                  style: AppTextStyles.tableNum,
                ),
                if (row.avgMonthly > 0) _MomentumChip(pct: row.momentum),
              ],
            ),
          ),
          // Order qty
          Expanded(
            flex: 2,
            child: critical && !needsOrder
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Out of stock',
                        textAlign: TextAlign.right,
                        style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'No sales data',
                        textAlign: TextAlign.right,
                        style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSubdued, fontSize: 10),
                      ),
                    ],
                  )
                : Text(
                    needsOrder ? '${rec.suggestedOrderQty}' : '—',
                    textAlign: TextAlign.right,
                    style: AppTextStyles.tableNum.copyWith(
                      color: needsOrder ? AppColors.primary : AppColors.textSubdued,
                      fontWeight: needsOrder ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
          ),
          // Order by
          Expanded(
            flex: 2,
            child: Text(
              needsOrder ? _formatDate(rec.recommendedOrderDate) : '—',
              style: AppTextStyles.tableCell,
            ),
          ),
          // Send to
          Expanded(
            flex: 3,
            child: noRecipient
                ? Tooltip(
                    message:
                        'This product has no supplier or manufacturer linked.\n'
                        'Tap to open the product and set one up.',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => showProductEditDialog(context, p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color:
                                  AppColors.warning.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_circle_outline,
                                size: 13, color: AppColors.warning),
                            const SizedBox(width: 5),
                            Text(
                              'Set supplier',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : Text(
                    recipient,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.tableCell,
                  ),
          ),
          // Approve
          SizedBox(
            width: 130,
            child: needsOrder
                ? noRecipient
                    ? Tooltip(
                        message:
                            'Set a supplier or manufacturer first to approve this order.',
                        child: OutlinedButton.icon(
                          onPressed: () {
                        showProductEditDialog(context, p);
                      },
                          icon: const Icon(Icons.edit_outlined, size: 14),
                          label: const Text('Set up'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.warning,
                            side: BorderSide(
                                color: AppColors.warning.withValues(alpha: 0.6)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                          ),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: busy ? null : onApprove,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        child: const Text('Approve'),
                      )
                : Text('OK',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}

class _EmptyState extends StatelessWidget {
  final int hiddenHealthyCount;
  final int totalProducts;
  const _EmptyState({
    this.hiddenHealthyCount = 0,
    this.totalProducts = 0,
  });

  @override
  Widget build(BuildContext context) {
    final hasProducts = totalProducts > 0;
    final allHealthy = hasProducts && hiddenHealthyCount == totalProducts;
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(
            allHealthy
                ? Icons.check_circle_outline
                : Icons.inventory_2_outlined,
            size: 48,
            color: allHealthy ? AppColors.success : AppColors.textSubdued,
          ),
          const SizedBox(height: 12),
          Text(
            allHealthy
                ? 'All stocked up'
                : (hasProducts
                    ? 'No low-stock products'
                    : 'No products yet'),
            style: AppTextStyles.h3.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            allHealthy
                ? 'Every product can cover its lead time at the current sales rate. Nothing to reorder right now.'
                : (hasProducts
                    ? 'Products only appear here when their stock can\'t cover the lead time at the recent sales rate. Import sales from Shopify so we can detect when stock runs low.'
                    : 'Connect Shopify or add products manually to see your reorder plan.'),
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppColors.textSubdued),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => context.go('/products'),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Products'),
          ),
        ],
      ),
    );
  }
}

// ── Window pickers ─────────────────────────────────────────────────────────

class _WindowPickers extends StatelessWidget {
  final int coverageDays;
  final List<int> coverageOptions;
  final int salesWindowDays;
  final List<int> windowOptions;
  final ValueChanged<int> onCoverageChanged;
  final ValueChanged<int> onWindowChanged;

  const _WindowPickers({
    required this.coverageDays,
    required this.coverageOptions,
    required this.salesWindowDays,
    required this.windowOptions,
    required this.onCoverageChanged,
    required this.onWindowChanged,
  });

  String _label(int days) {
    if (days % 30 == 0) {
      final m = days ~/ 30;
      return m == 1 ? '1 month' : '$m months';
    }
    return '$days days';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _PickerField(
            label: 'Order should cover',
            hint: 'How long this order needs to last',
            value: coverageDays,
            options: coverageOptions,
            labelFn: _label,
            onChanged: onCoverageChanged,
          ),
          _PickerField(
            label: 'Based on sales over',
            hint: 'Recent window for the daily average',
            value: salesWindowDays,
            options: windowOptions,
            labelFn: _label,
            onChanged: onWindowChanged,
          ),
        ],
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  final String label;
  final String hint;
  final int value;
  final List<int> options;
  final String Function(int) labelFn;
  final ValueChanged<int> onChanged;

  const _PickerField({
    required this.label,
    required this.hint,
    required this.value,
    required this.options,
    required this.labelFn,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        DropdownButton<int>(
          value: value,
          underline: const SizedBox.shrink(),
          items: options
              .map((o) => DropdownMenuItem(
                    value: o,
                    child: Text(labelFn(o)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
        Text(hint,
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSubdued, fontSize: 11)),
      ],
    );
  }
}

// ── Momentum chip ──────────────────────────────────────────────────────────

class _MomentumChip extends StatelessWidget {
  final double pct;
  const _MomentumChip({required this.pct});

  @override
  Widget build(BuildContext context) {
    if (pct.abs() < 0.05) {
      return Text('flat',
          style: AppTextStyles.bodySmall
              .copyWith(color: AppColors.textSubdued, fontSize: 11));
    }
    final up = pct > 0;
    final color = up ? AppColors.success : AppColors.error;
    final icon = up ? Icons.arrow_upward : Icons.arrow_downward;
    final label = '${(pct * 100).abs().round()}%';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 2),
        Text(label,
            style: AppTextStyles.bodySmall.copyWith(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ── Data quality banner (Phase 1.3) ────────────────────────────────────────
//
// The reorder plan is only as accurate as the upstream data. We surface the
// three most common silent-zero scenarios so the user can fix them before
// trusting any numbers on this screen:
//
//   1. Manufactured products with no BOM  → cost falls back to 0.
//   2. Raw materials with unitCost == 0   → BOMs roll up to 0.
//   3. Purchased products with unitCost==0 → user never typed cost.
//
// If everything is clean, the banner doesn't render (zero clutter).
class _DataQualityBanner extends StatelessWidget {
  final AppState state;
  final List<Product> products;
  const _DataQualityBanner({required this.state, required this.products});

  @override
  Widget build(BuildContext context) {
    final issues = <_DataQualityIssue>[];

    // 1) Manufactured without BOM
    final mfgWithoutBom = products.where((p) {
      final isMfg = p.manufacturerId != null && p.manufacturerId!.isNotEmpty;
      if (!isMfg) return false;
      final bom = state.boms
          .where((b) => b.finalProductId == p.id && b.isActive)
          .toList();
      return bom.isEmpty || bom.first.materials.isEmpty;
    }).toList();
    if (mfgWithoutBom.isNotEmpty) {
      issues.add(_DataQualityIssue(
        icon: Icons.precision_manufacturing_outlined,
        title:
            '${mfgWithoutBom.length} manufactured product${mfgWithoutBom.length == 1 ? '' : 's'} missing a recipe',
        body:
            'Cost will show as 0 until you set up the Bill of Materials. Reorder math will be wrong.',
        actionLabel: 'Set up recipes',
        onAction: () => context.go('/bom'),
      ));
    }

    // 2) Raw materials with no cost
    final rmNoCost = state.rawMaterials.where((m) => m.unitCost <= 0).toList();
    if (rmNoCost.isNotEmpty) {
      issues.add(_DataQualityIssue(
        icon: Icons.science_outlined,
        title:
            '${rmNoCost.length} raw material${rmNoCost.length == 1 ? '' : 's'} with no unit cost',
        body:
            'Manufactured product costs depend on these. Set a cost on each so the BOM rolls up correctly.',
        actionLabel: 'Open Raw Materials',
        onAction: () => context.go('/raw-materials'),
      ));
    }

    // 3) Purchased products with no cost
    final purchasedNoCost = products.where((p) {
      final isMfg = p.manufacturerId != null && p.manufacturerId!.isNotEmpty;
      if (isMfg) return false;
      if (p.isBundle) return false; // bundle cost derives from components
      return p.unitCost <= 0;
    }).toList();
    if (purchasedNoCost.isNotEmpty) {
      issues.add(_DataQualityIssue(
        icon: Icons.attach_money,
        title:
            '${purchasedNoCost.length} purchased product${purchasedNoCost.length == 1 ? '' : 's'} with no cost',
        body:
            'Open each product and type what your supplier charges. Without it, your inventory cost is understated.',
        actionLabel: 'Open Products',
        onAction: () => context.go('/products'),
      ));
    }

    if (issues.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.warning, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Fix these before trusting the numbers',
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < issues.length; i++) ...[
              if (i > 0)
                Divider(
                  color: AppColors.warning.withValues(alpha: 0.2),
                  height: 18,
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(issues[i].icon, size: 18, color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(issues[i].title,
                            style: AppTextStyles.body.copyWith(
                                fontWeight: FontWeight.w600, fontSize: 13.5)),
                        const SizedBox(height: 2),
                        Text(issues[i].body,
                            style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: issues[i].onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.warning,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(issues[i].actionLabel,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12.5)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DataQualityIssue {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  _DataQualityIssue({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });
}
