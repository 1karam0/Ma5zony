import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/services/supply_chain_insights_service.dart';
import 'package:ma5zony/utils/constants.dart';

/// Supply-Chain Insights screen.
///
/// Renders the output of [SupplyChainInsightsService] (Chopra & Meindl
/// coordination / bullwhip / supplier-reliability / movement-classification).
///
/// Strictly additive — does not touch any existing screen, navigation flow,
/// or tour. Pulls all data from `AppState`.
class SupplyChainInsightsScreen extends StatefulWidget {
  const SupplyChainInsightsScreen({super.key});

  @override
  State<SupplyChainInsightsScreen> createState() =>
      _SupplyChainInsightsScreenState();
}

class _SupplyChainInsightsScreenState extends State<SupplyChainInsightsScreen> {
  final _service = SupplyChainInsightsService();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final insights = _service.analyse(
      products: state.products,
      demandByProduct: state.demandByProduct,
      purchaseOrders: state.purchaseOrders,
      suppliers: {for (final s in state.suppliers) s.id: s},
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 24),
          _overallStrip(insights),
          const SizedBox(height: 24),
          if (insights.alerts.isNotEmpty) ...[
            _sectionTitle('Alerts'),
            const SizedBox(height: 12),
            ...insights.alerts.map(_alertCard),
            const SizedBox(height: 24),
          ],
          _sectionTitle('Bullwhip risk by product'),
          const SizedBox(height: 8),
          Text(
            'Compares how much your purchase orders fluctuate versus actual demand. '
            'A value of 1.0 means orders are perfectly in step with demand; values '
            'much greater than 1.0 indicate amplification (the "bullwhip effect").',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 12),
          _bullwhipTable(insights),
          const SizedBox(height: 24),
          _sectionTitle('Supplier reliability'),
          const SizedBox(height: 8),
          Text(
            'Composite 0–100 score from on-time delivery, order completion rate, '
            'and your manual rating.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 12),
          _reliabilityTable(insights),
          const SizedBox(height: 24),
          _sectionTitle('Product movement & strategy'),
          const SizedBox(height: 12),
          _movementTable(insights),
          const SizedBox(height: 24),
          _sectionTitle('Information sharing checklist'),
          const SizedBox(height: 12),
          _infoSharingCard(insights),
          const SizedBox(height: 32),
          _footnote(),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Supply Chain Insights', style: AppTextStyles.h1),
        const SizedBox(height: 6),
        Text(
          'Bullwhip risk, supplier reliability, and movement-based inventory '
          'strategy — based on Chopra & Meindl coordination principles.',
          style: AppTextStyles.bodySmall,
        ),
      ],
    );
  }

  // ── Overall strip ──────────────────────────────────────────────────────

  Widget _overallStrip(SupplyChainInsights insights) {
    final bw = insights.overallBullwhipRisk;
    final goodSuppliers =
        insights.supplierReliability.where((r) => r.score >= 70).length;
    final fastMovers = insights.productMovements
        .where((m) => m.category == MovementCategory.fast)
        .length;
    final riskyProducts = insights.productMovements
        .where((m) => m.category == MovementCategory.risky)
        .length;

    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            label: 'Overall bullwhip risk',
            value: _bullwhipLabel(bw),
            color: _bullwhipColor(bw),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            label: 'Reliable suppliers',
            value: '$goodSuppliers / ${insights.supplierReliability.length}',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            label: 'Fast-moving products',
            value: '$fastMovers',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            label: 'Risky products',
            value: '$riskyProducts',
            color: riskyProducts > 0 ? AppColors.warning : AppColors.success,
          ),
        ),
      ],
    );
  }

  Widget _kpiCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text(value,
              style:
                  AppTextStyles.h2.copyWith(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ── Alerts ─────────────────────────────────────────────────────────────

  Widget _alertCard(SupplyChainAlert a) {
    Color bg;
    IconData icon;
    Color iconColor;
    switch (a.severity) {
      case AlertSeverity.high:
        bg = const Color(0xFFFDECEA);
        icon = Icons.error_outline;
        iconColor = AppColors.error;
        break;
      case AlertSeverity.medium:
        bg = const Color(0xFFFFF4E5);
        icon = Icons.warning_amber_outlined;
        iconColor = AppColors.warning;
        break;
      case AlertSeverity.low:
        bg = const Color(0xFFE3F2FD);
        icon = Icons.info_outline;
        iconColor = const Color(0xFF1D5FA3);
        break;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title,
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(a.message, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bullwhip table ─────────────────────────────────────────────────────

  Widget _bullwhipTable(SupplyChainInsights insights) {
    final rows = [...insights.bullwhipByProduct]
      ..sort((a, b) => b.bullwhipRatio.compareTo(a.bullwhipRatio));
    if (rows.isEmpty) return _emptyHint('No product data yet.');
    return _tableCard(
      headers: const ['Product', 'Demand σ²', 'Order σ²', 'Ratio', 'Risk'],
      rows: rows.map((r) {
        return [
          r.productName,
          r.demandVariance.toStringAsFixed(1),
          r.orderVariance.toStringAsFixed(1),
          r.bullwhipRatio >= 99
              ? '∞'
              : '${r.bullwhipRatio.toStringAsFixed(2)}×',
          _bullwhipChip(r.risk),
        ];
      }).toList(),
    );
  }

  Widget _bullwhipChip(BullwhipRisk r) {
    final color = _bullwhipColor(r);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _bullwhipLabel(r),
        style: AppTextStyles.bodySmall
            .copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _bullwhipLabel(BullwhipRisk r) => switch (r) {
        BullwhipRisk.low => 'Low',
        BullwhipRisk.medium => 'Medium',
        BullwhipRisk.high => 'High',
        BullwhipRisk.insufficientData => 'Insufficient data',
      };

  Color _bullwhipColor(BullwhipRisk r) => switch (r) {
        BullwhipRisk.low => AppColors.success,
        BullwhipRisk.medium => AppColors.warning,
        BullwhipRisk.high => AppColors.error,
        BullwhipRisk.insufficientData => AppColors.textSecondary,
      };

  // ── Reliability table ──────────────────────────────────────────────────

  Widget _reliabilityTable(SupplyChainInsights insights) {
    if (insights.supplierReliability.isEmpty) {
      return _emptyHint('Add suppliers to see reliability scores.');
    }
    final rows = [...insights.supplierReliability]
      ..sort((a, b) => b.score.compareTo(a.score));
    return _tableCard(
      headers: const ['Supplier', 'Orders', 'On-time', 'Score', 'Grade'],
      rows: rows.map((s) {
        return [
          s.supplierName,
          s.totalOrders.toString(),
          s.totalOrders == 0 ? '—' : '${(s.onTimeRate * 100).round()}%',
          '${s.score}/100',
          _gradeChip(s.grade, s.score),
        ];
      }).toList(),
    );
  }

  Widget _gradeChip(String grade, int score) {
    Color c;
    if (score >= 85) {
      c = AppColors.success;
    } else if (score >= 55) {
      c = AppColors.warning;
    } else {
      c = AppColors.error;
    }
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(grade,
          style: AppTextStyles.bodySmall
              .copyWith(color: c, fontWeight: FontWeight.w700)),
    );
  }

  // ── Movement table ─────────────────────────────────────────────────────

  Widget _movementTable(SupplyChainInsights insights) {
    if (insights.productMovements.isEmpty) {
      return _emptyHint('No product data yet.');
    }
    final rows = [...insights.productMovements]
      ..sort((a, b) => b.velocityPerDay.compareTo(a.velocityPerDay));
    return _tableCard(
      headers: const [
        'Product',
        'Velocity (u/day)',
        'Variability (CV)',
        'Category',
        'Recommendation'
      ],
      rows: rows.map((m) {
        return [
          m.productName,
          m.velocityPerDay.toStringAsFixed(2),
          m.demandCv.toStringAsFixed(2),
          _movementChip(m.category),
          SizedBox(
            width: 280,
            child: Text(m.recommendation, style: AppTextStyles.bodySmall),
          ),
        ];
      }).toList(),
    );
  }

  Widget _movementChip(MovementCategory c) {
    final (label, color) = switch (c) {
      MovementCategory.fast => ('Fast', AppColors.success),
      MovementCategory.stable => ('Stable', AppColors.primary),
      MovementCategory.slow => ('Slow', AppColors.textSecondary),
      MovementCategory.risky => ('Risky', AppColors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: AppTextStyles.bodySmall
              .copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }

  // ── Information sharing ────────────────────────────────────────────────

  Widget _infoSharingCard(SupplyChainInsights insights) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: insights.informationSharingChecklist
            .map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 18, color: AppColors.success),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item, style: AppTextStyles.body)),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Widget _sectionTitle(String t) =>
      Text(t, style: AppTextStyles.h2.copyWith(fontWeight: FontWeight.w700));

  Widget _emptyHint(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(msg,
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary)),
      );

  Widget _tableCard({
    required List<String> headers,
    required List<List<Object>> rows,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: AppTextStyles.bodySmall
              .copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          dataTextStyle: AppTextStyles.bodySmall,
          columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
          rows: rows
              .map(
                (r) => DataRow(
                  cells: r
                      .map((c) => DataCell(
                          c is Widget ? c : Text(c.toString())))
                      .toList(),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _footnote() => Text(
        'Based on Chopra & Meindl, Supply Chain Management: Strategy, '
        'Planning, and Operation. Bullwhip ratio uses monthly demand vs. '
        'monthly purchase-order quantity variance. Reliability composite: '
        '50% on-time, 20% completion rate, 30% manual rating.',
        style: AppTextStyles.bodySmall
            .copyWith(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
      );
}
