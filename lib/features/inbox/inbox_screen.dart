import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:ma5zony/models/manufacturing_recommendation.dart';
import 'package:ma5zony/models/production_order.dart';
import 'package:ma5zony/models/purchase_order.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

// ── Data model ────────────────────────────────────────────────────────────────

enum _Severity { critical, warning, info }

class _ActionItem {
  final _Severity severity;
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final String route;

  const _ActionItem({
    required this.severity,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.route,
  });

  Color get color => switch (severity) {
        _Severity.critical => AppColors.error,
        _Severity.warning => AppColors.warning,
        _Severity.info => AppColors.primary,
      };

  Color get bgColor => switch (severity) {
        _Severity.critical => const Color(0xFFFFF1F1),
        _Severity.warning => const Color(0xFFFFF8E1),
        _Severity.info => const Color(0xFFF0F4FF),
      };
}

// ── Screen ────────────────────────────────────────────────────────────────────

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  List<_ActionItem> _buildItems(AppState state) {
    final items = <_ActionItem>[];

    // 1. Critical stock
    for (final r in state.criticalStockProducts) {
      final days = r.daysOfStockLeft.toStringAsFixed(1);
      items.add(_ActionItem(
        severity: _Severity.critical,
        icon: Icons.warning_amber_rounded,
        title: '${r.productName} — critical stock',
        subtitle: '${r.currentStock} units left · ~${days}d of coverage · '
            'ROP: ${r.minimumStock}',
        actionLabel: 'Run Forecast',
        route: '/forecasts?productId=${r.productId}',
      ));
    }

    // 2. Open replenishment recommendations
    final openRecs = state.recommendations
        .where((r) => !state.approvedRecommendations.contains(r.productId))
        .where(
            (r) => r.status == 'Critical' || r.status == 'Order Now')
        .toList();
    if (openRecs.isNotEmpty) {
      items.add(_ActionItem(
        severity: _Severity.warning,
        icon: Icons.refresh_outlined,
        title: '${openRecs.length} product${openRecs.length == 1 ? '' : 's'} need replenishment',
        subtitle: openRecs
                .take(3)
                .map((r) => r.productName)
                .join(', ') +
            (openRecs.length > 3 ? ' and ${openRecs.length - 3} more' : ''),
        actionLabel: 'Review & Approve',
        route: '/replenishment',
      ));
    }

    // 3. Draft POs awaiting confirmation
    final draftPos = state.purchaseOrders
        .where((o) => o.status == OrderStatus.draft)
        .toList();
    if (draftPos.isNotEmpty) {
      items.add(_ActionItem(
        severity: _Severity.info,
        icon: Icons.receipt_long_outlined,
        title:
            '${draftPos.length} draft purchase order${draftPos.length == 1 ? '' : 's'} awaiting confirmation',
        subtitle:
            '${draftPos.take(3).map((o) => '${o.items.length} item${o.items.length == 1 ? '' : 's'}').join(', ')} — confirm to send to suppliers',
        actionLabel: 'Go to Orders',
        route: '/orders',
      ));
    }

    // 4. Pending manufacturing recommendations
    final pendingMfg = state.mfgRecommendations
        .where((r) => r.status == RecommendationStatus.pending)
        .toList();
    if (pendingMfg.isNotEmpty) {
      items.add(_ActionItem(
        severity: _Severity.warning,
        icon: Icons.precision_manufacturing_outlined,
        title:
            '${pendingMfg.length} manufacturing recommendation${pendingMfg.length == 1 ? '' : 's'} pending review',
        subtitle: pendingMfg
                .take(3)
                .map((r) {
                  final productName = state.products
                      .where((p) => p.id == r.productId)
                      .firstOrNull
                      ?.name;
                  return productName ?? r.productId;
                })
                .join(', ') +
            (pendingMfg.length > 3
                ? ' and ${pendingMfg.length - 3} more'
                : ''),
        actionLabel: 'Review Recommendations',
        route: '/recommendations',
      ));
    }

    // 5. Production orders needing attention
    final activeProd = state.productionOrders
        .where((o) =>
            o.status == ProductionOrderStatus.draft ||
            o.status == ProductionOrderStatus.approved ||
            o.status == ProductionOrderStatus.materialsOrdered)
        .toList();
    if (activeProd.isNotEmpty) {
      items.add(_ActionItem(
        severity: _Severity.info,
        icon: Icons.factory_outlined,
        title:
            '${activeProd.length} production order${activeProd.length == 1 ? '' : 's'} in progress',
        subtitle: activeProd
            .take(3)
            .map((o) => '${o.quantity}× (${_statusLabel(o.status)})')
            .join(', '),
        actionLabel: 'View Production Orders',
        route: '/production-orders',
      ));
    }

    // 6. Supplier responses needing acknowledgement
    final responses = state.supplierOrders
        .where((o) =>
            o.status == 'acknowledged' && o.response != null)
        .toList();
    if (responses.isNotEmpty) {
      items.add(_ActionItem(
        severity: _Severity.info,
        icon: Icons.mark_email_unread_outlined,
        title:
            '${responses.length} supplier response${responses.length == 1 ? '' : 's'} received',
        subtitle: responses
            .take(3)
            .map((o) {
              final resp = o.response!;
              return '${o.supplierName}: '
                  '${resp.estimatedDeliveryDays != null ? "${resp.estimatedDeliveryDays}d delivery" : "responded"}';
            })
            .join(' · '),
        actionLabel: 'Review Responses',
        route: '/orders',
      ));
    }

    return items;
  }

  String _statusLabel(ProductionOrderStatus s) => switch (s) {
        ProductionOrderStatus.draft => 'Draft',
        ProductionOrderStatus.approved => 'Approved',
        ProductionOrderStatus.materialsOrdered => 'Materials Ordered',
        ProductionOrderStatus.materialsReady => 'Materials Ready',
        ProductionOrderStatus.inProduction => 'In Production',
        ProductionOrderStatus.completed => 'Completed',
      };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = _buildItems(state);

    final criticalCount =
        items.where((i) => i.severity == _Severity.critical).length;
    final warningCount =
        items.where((i) => i.severity == _Severity.warning).length;
    final infoCount =
        items.where((i) => i.severity == _Severity.info).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Action Center'),
          if (items.isEmpty)
            _EmptyInbox()
          else ...[
            // Summary KPIs
            Row(
              children: [
                if (criticalCount > 0)
                  Expanded(
                    child: KPICard(
                      title: 'Critical',
                      value: '$criticalCount',
                      icon: Icons.warning_amber_rounded,
                      color: AppColors.error,
                      isAlert: true,
                    ),
                  ),
                if (criticalCount > 0) const SizedBox(width: 12),
                if (warningCount > 0)
                  Expanded(
                    child: KPICard(
                      title: 'Need Action',
                      value: '$warningCount',
                      icon: Icons.pending_actions,
                      color: AppColors.warning,
                    ),
                  ),
                if (warningCount > 0) const SizedBox(width: 12),
                if (infoCount > 0)
                  Expanded(
                    child: KPICard(
                      title: 'In Progress',
                      value: '$infoCount',
                      icon: Icons.autorenew,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // Grouped items: critical first, then warnings, then info
            ...items.map((item) => _ActionCard(item: item)),
          ],
        ],
      ),
    );
  }
}

// ── Empty inbox ───────────────────────────────────────────────────────────────

class _EmptyInbox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 72, color: AppColors.success.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            const Text('All clear — no actions needed',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text(
              'Your inventory is healthy, all orders are confirmed,\n'
              'and there are no pending approvals.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action card ───────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final _ActionItem item;
  const _ActionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: item.color.withValues(alpha: 0.3)),
      ),
      color: item.bgColor,
      child: InkWell(
        onTap: () => context.go(item.route),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.icon, color: item.color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: item.color),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              OutlinedButton(
                onPressed: () => context.go(item.route),
                style: OutlinedButton.styleFrom(
                  foregroundColor: item.color,
                  side: BorderSide(color: item.color.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.actionLabel),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward, size: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
