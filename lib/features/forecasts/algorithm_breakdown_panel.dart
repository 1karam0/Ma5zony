import 'package:flutter/material.dart';
import 'package:ma5zony/models/forecast_result.dart';
import 'package:ma5zony/utils/constants.dart';

/// Algorithm Transparency Panel
///
/// A key differentiator for Ma5zony over commercial tools (Odoo, Zoho, TradeGecko).
/// As described in the interim report Section 2.5, this panel provides users with
/// full visibility into the mathematical breakdown of each forecast, enabling
/// them to understand *why* certain recommendations are made.
///
/// Displays:
///   - Algorithm name and formula
///   - Parameters used (α, β, γ, window size)
///   - Accuracy metrics (MAE, MAPE, RMSE)
///   - Step-by-step computation breakdown
///   - Confidence intervals
class AlgorithmBreakdownPanel extends StatelessWidget {
  final ForecastResult result;
  final bool expanded;

  const AlgorithmBreakdownPanel({
    super.key,
    required this.result,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.md,
        boxShadow: AppShadows.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.functions,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          title: Text(
            'Algorithm Breakdown',
            style: AppTextStyles.h3,
          ),
          subtitle: Text(
            _algorithmFullName(result.algorithm),
            style: AppTextStyles.bodySmall,
          ),
          children: [
            const Divider(),
            const SizedBox(height: 12),

            // ── Formula Section ───────────────────────────────────────────
            _FormulaCard(algorithm: result.algorithm),
            const SizedBox(height: 16),

            // ── Parameters Section ────────────────────────────────────────
            _ParametersSection(params: result.algorithmParams),
            const SizedBox(height: 16),

            // ── Accuracy Metrics ──────────────────────────────────────────
            _AccuracyMetricsRow(result: result),
            const SizedBox(height: 16),

            // ── Computation Steps ─────────────────────────────────────────
            if (result.forecast.length > 1)
              _ComputationStepsTable(result: result),
            const SizedBox(height: 16),

            // ── Interpretation ────────────────────────────────────────────
            _InterpretationCard(result: result),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  static String _algorithmFullName(String code) {
    switch (code) {
      case 'SMA':
        return 'Simple Moving Average';
      case 'WMA':
        return 'Weighted Moving Average';
      case 'SES':
        return 'Single Exponential Smoothing';
      case 'Holt':
        return "Holt's Double Exponential Smoothing";
      case 'HoltWinters':
        return 'Holt-Winters Triple Exponential Smoothing';
      default:
        return code;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FORMULA CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _FormulaCard extends StatelessWidget {
  final String algorithm;
  const _FormulaCard({required this.algorithm});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: AppRadius.sm,
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 14, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(
                'Formula',
                style: AppTextStyles.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _formulaText(),
            style: AppTextStyles.body.copyWith(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _formulaExplanation(),
            style: AppTextStyles.bodySmall.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }

  String _formulaText() {
    switch (algorithm) {
      case 'SMA':
        return 'F(t+1) = (1/n) × Σ D(i)  for i = t-n+1 to t';
      case 'WMA':
        return 'F(t+1) = Σ(w(i) × D(i)) / Σ w(i)';
      case 'SES':
        return 'F(t+1) = α × D(t) + (1 - α) × F(t)';
      case 'Holt':
        return 'L(t) = α × D(t) + (1 - α) × (L(t-1) + T(t-1))\n'
            'T(t) = β × (L(t) - L(t-1)) + (1 - β) × T(t-1)\n'
            'F(t+1) = L(t) + T(t)';
      case 'HoltWinters':
        return 'L(t) = α × (D(t) - S(t-s)) + (1 - α) × (L(t-1) + T(t-1))\n'
            'T(t) = β × (L(t) - L(t-1)) + (1 - β) × T(t-1)\n'
            'S(t) = γ × (D(t) - L(t)) + (1 - γ) × S(t-s)\n'
            'F(t+m) = L(t) + m × T(t) + S(t-s+m)';
      default:
        return 'F(t+1) = f(D(1)...D(t))';
    }
  }

  String _formulaExplanation() {
    switch (algorithm) {
      case 'SMA':
        return 'D = actual demand, n = window size, F = forecast. '
            'Simple average of the last n observed demand values.';
      case 'WMA':
        return 'D = demand, w = weight (higher for recent periods). '
            'Recent data has more influence on the forecast.';
      case 'SES':
        return 'α = smoothing factor (0-1), D = actual demand, F = forecast. '
            'Higher α = more responsive to recent changes.';
      case 'Holt':
        return 'L = level, T = trend, α = level smoothing, β = trend smoothing. '
            'Captures both base demand and growth/decline direction.';
      case 'HoltWinters':
        return 'L = level, T = trend, S = seasonal component, s = season length. '
            'Decomposes demand into base level, trend, and repeating seasonal pattern.';
      default:
        return '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PARAMETERS SECTION
// ═══════════════════════════════════════════════════════════════════════════════

class _ParametersSection extends StatelessWidget {
  final Map<String, double> params;
  const _ParametersSection({required this.params});

  @override
  Widget build(BuildContext context) {
    if (params.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Parameters', style: AppTextStyles.label.copyWith(
          fontWeight: FontWeight.w600,
        )),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: params.entries.map((e) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _paramLabel(e.key),
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '= ${_formatValue(e.key, e.value)}',
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _paramLabel(String key) {
    switch (key) {
      case 'alpha':
        return 'α';
      case 'beta':
        return 'β';
      case 'gamma':
        return 'γ';
      case 'windowSize':
        return 'Window';
      case 'seasonLength':
        return 'Season';
      default:
        return key;
    }
  }

  String _formatValue(String key, double value) {
    if (key == 'windowSize' || key == 'seasonLength') {
      return '${value.toInt()}';
    }
    if (key.startsWith('w')) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ACCURACY METRICS ROW
// ═══════════════════════════════════════════════════════════════════════════════

class _AccuracyMetricsRow extends StatelessWidget {
  final ForecastResult result;
  const _AccuracyMetricsRow({required this.result});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (result.mae != null)
          _MetricChip(
            label: 'MAE',
            value: result.mae!.toStringAsFixed(1),
            tooltip: 'Mean Absolute Error — average magnitude of forecast errors',
            color: AppColors.info,
          ),
        if (result.mape != null)
          _MetricChip(
            label: 'MAPE',
            value: '${(result.mape! * 100).toStringAsFixed(1)}%',
            tooltip: 'Mean Absolute Percentage Error — accuracy as a percentage',
            color: _mapeColor(result.mape!),
          ),
        if (result.rmse != null)
          _MetricChip(
            label: 'RMSE',
            value: result.rmse!.toStringAsFixed(1),
            tooltip:
                'Root Mean Squared Error — penalises large errors more than MAE',
            color: AppColors.accent,
          ),
      ],
    );
  }

  Color _mapeColor(double mape) {
    if (mape < 0.10) return AppColors.success; // <10% = excellent
    if (mape < 0.20) return AppColors.info; // <20% = good
    if (mape < 0.50) return AppColors.warning; // <50% = acceptable
    return AppColors.error; // >50% = poor
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final String tooltip;
  final Color color;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.tooltip,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: AppRadius.sm,
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.labelSmall.copyWith(color: color),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTextStyles.h3.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPUTATION STEPS TABLE
// ═══════════════════════════════════════════════════════════════════════════════

class _ComputationStepsTable extends StatelessWidget {
  final ForecastResult result;
  const _ComputationStepsTable({required this.result});

  @override
  Widget build(BuildContext context) {
    // Show last 6 periods + the forecast period
    final totalPeriods = result.periods.length;
    final startIdx = totalPeriods > 7 ? totalPeriods - 7 : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step-by-Step Computation',
            style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: AppRadius.sm,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.sm,
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1.5),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1),
              },
              border: TableBorder(
                horizontalInside: BorderSide(color: AppColors.borderLight),
                verticalInside: BorderSide(color: AppColors.borderLight),
              ),
              children: [
                // Header row
                TableRow(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                  ),
                  children: [
                    _headerCell('Period'),
                    _headerCell('Actual'),
                    _headerCell('Forecast'),
                    _headerCell('Error'),
                  ],
                ),
                // Data rows
                for (int i = startIdx; i < totalPeriods; i++)
                  _dataRow(i, i == totalPeriods - 1),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(text, style: AppTextStyles.label.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        )),
      );

  TableRow _dataRow(int index, bool isForecast) {
    final period = result.periods[index];
    final actual = result.actualDemand[index];
    final forecast = result.forecast[index];
    final error = actual > 0 ? (actual - forecast).abs() : null;

    final periodLabel = isForecast
        ? '${_monthLabel(period)} ★'
        : _monthLabel(period);

    return TableRow(
      decoration: BoxDecoration(
        color: isForecast
            ? AppColors.primaryLight
            : Colors.transparent,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            periodLabel,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: isForecast ? FontWeight.w600 : FontWeight.normal,
              color: isForecast ? AppColors.primary : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            isForecast ? '—' : actual.toStringAsFixed(0),
            style: AppTextStyles.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            forecast.toStringAsFixed(1),
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: isForecast ? AppColors.primary : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            isForecast ? '—' : (error?.toStringAsFixed(1) ?? '—'),
            style: AppTextStyles.bodySmall.copyWith(
              color: error != null && error > (actual * 0.2)
                  ? AppColors.warning
                  : AppColors.textSubdued,
            ),
          ),
        ),
      ],
    );
  }

  String _monthLabel(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTERPRETATION CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _InterpretationCard extends StatelessWidget {
  final ForecastResult result;
  const _InterpretationCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final mape = result.mape;
    final forecast = result.nextPeriodForecast;

    String quality;
    Color qualityColor;
    IconData qualityIcon;

    if (mape == null || mape > 0.5) {
      quality = 'Low confidence';
      qualityColor = AppColors.error;
      qualityIcon = Icons.warning_amber;
    } else if (mape > 0.2) {
      quality = 'Moderate confidence';
      qualityColor = AppColors.warning;
      qualityIcon = Icons.info_outline;
    } else if (mape > 0.1) {
      quality = 'Good confidence';
      qualityColor = AppColors.info;
      qualityIcon = Icons.thumb_up_outlined;
    } else {
      quality = 'High confidence';
      qualityColor = AppColors.success;
      qualityIcon = Icons.verified;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: qualityColor.withValues(alpha: 0.06),
        borderRadius: AppRadius.sm,
        border: Border.all(color: qualityColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(qualityIcon, size: 20, color: qualityColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quality,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: qualityColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Next period forecast: ${forecast.toStringAsFixed(0)} units. '
                  '${_interpretationText()}',
                  style: AppTextStyles.bodySmall.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _interpretationText() {
    final mape = result.mape;
    if (mape == null) return 'Insufficient data to assess forecast quality.';
    if (mape < 0.10) {
      return 'The forecast closely tracks historical demand. '
          'Recommendations based on this forecast are highly reliable.';
    }
    if (mape < 0.20) {
      return 'The forecast captures the general demand pattern well. '
          'Consider adding a small safety buffer for unexpected spikes.';
    }
    if (mape < 0.50) {
      return 'Demand shows moderate variability. Consider increasing '
          'safety stock or using a more adaptive algorithm.';
    }
    return 'Demand is highly unpredictable. Use generous safety stock '
        'and consider manual review of this product\'s ordering strategy.';
  }
}
