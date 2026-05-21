import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/models/forecast_result.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';

/// Side-by-side comparison of all forecasting algorithms for a single product.
///
/// Uses [AppState.compareForecastAlgorithms] which runs SMA, WMA, SES, Holt
/// and Holt-Winters in parallel and exposes the results via
/// [AppState.forecastComparison].
class ForecastComparisonScreen extends StatefulWidget {
  const ForecastComparisonScreen({super.key});

  @override
  State<ForecastComparisonScreen> createState() =>
      _ForecastComparisonScreenState();
}

class _ForecastComparisonScreenState extends State<ForecastComparisonScreen> {
  String? _productId;
  bool _running = false;

  static const _algoColors = {
    'SMA': AppColors.chart1,
    'WMA': AppColors.chart2,
    'SES': AppColors.chart3,
    'Holt': AppColors.chart4,
    'HoltWinters': AppColors.chart5,
  };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final products = state.products;

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (products.isEmpty) {
      return const Center(child: Text('No products available.'));
    }

    _productId ??= products.first.id;
    final comparison = state.forecastComparison;
    final best = _bestByMape(comparison);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Forecast Algorithm Comparison', style: AppTextStyles.h1),
          const SizedBox(height: 6),
          Text(
            'Run all forecasting methods at once and pick the best for each product.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 20),

          // ── Controls ─────────────────────────────────────────────────────
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.md,
              side: const BorderSide(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _productId,
                      decoration: const InputDecoration(
                        labelText: 'Product',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: products
                          .map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.name,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _productId = v),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _running ? null : _run,
                    icon: _running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.compare_arrows),
                    label: const Text('Compare Algorithms'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          if (comparison.isEmpty)
            _emptyState()
          else ...[
            _metricsTable(comparison, best),
            const SizedBox(height: 20),
            _comparisonChart(comparison),
            if (best != null) ...[
              const SizedBox(height: 20),
              _bestBanner(best, comparison[best]!),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _run() async {
    if (_productId == null) return;
    setState(() => _running = true);
    try {
      await context.read<AppState>().compareForecastAlgorithms(_productId!);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String? _bestByMape(Map<String, ForecastResult> results) {
    String? winner;
    double bestMape = double.infinity;
    for (final entry in results.entries) {
      final m = entry.value.mape;
      if (m != null && m < bestMape) {
        bestMape = m;
        winner = entry.key;
      }
    }
    return winner;
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(48),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.md,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.bar_chart, size: 56, color: AppColors.textSubdued),
          const SizedBox(height: 12),
          Text('No comparison run yet', style: AppTextStyles.h3),
          const SizedBox(height: 6),
          Text(
            'Pick a product and click "Compare Algorithms" to run SMA, WMA, SES, Holt and Holt-Winters side-by-side.',
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _metricsTable(Map<String, ForecastResult> results, String? best) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.md,
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Accuracy Metrics', style: AppTextStyles.h3),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1.5),
                2: FlexColumnWidth(1.5),
                3: FlexColumnWidth(1.5),
                4: FlexColumnWidth(1.5),
              },
              border: TableBorder(
                horizontalInside:
                    BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: AppColors.background),
                  children: [
                    _headerCell('Algorithm'),
                    _headerCell('MAE'),
                    _headerCell('MAPE'),
                    _headerCell('RMSE'),
                    _headerCell('Next Forecast'),
                  ],
                ),
                for (final entry in results.entries)
                  TableRow(
                    decoration: entry.key == best
                        ? BoxDecoration(
                            color: AppColors.successBg.withValues(alpha: 0.3))
                        : null,
                    children: [
                      _bodyCell(_algoLabel(entry.key), bold: entry.key == best),
                      _bodyCell(entry.value.mae?.toStringAsFixed(2) ?? '—'),
                      _bodyCell(entry.value.mape != null
                          ? '${(entry.value.mape! * 100).toStringAsFixed(1)}%'
                          : '—'),
                      _bodyCell(entry.value.rmse?.toStringAsFixed(2) ?? '—'),
                      _bodyCell(
                          entry.value.nextPeriodForecast.toStringAsFixed(1)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(text, style: AppTextStyles.label),
      );

  Widget _bodyCell(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          text,
          style: AppTextStyles.body.copyWith(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      );

  String _algoLabel(String key) {
    switch (key) {
      case 'SMA':
        return 'Simple Moving Average';
      case 'WMA':
        return 'Weighted Moving Average';
      case 'SES':
        return 'Single Exponential Smoothing';
      case 'Holt':
        return "Holt's Double Smoothing";
      case 'HoltWinters':
        return 'Holt-Winters Triple Smoothing';
      default:
        return key;
    }
  }

  Widget _comparisonChart(Map<String, ForecastResult> results) {
    final first = results.values.first;
    final length = first.actualDemand.length;
    if (length == 0) return const SizedBox.shrink();

    final actualSpots = [
      for (int i = 0; i < length; i++)
        FlSpot(i.toDouble(), first.actualDemand[i]),
    ];

    final lines = <LineChartBarData>[
      LineChartBarData(
        spots: actualSpots,
        isCurved: false,
        color: AppColors.textPrimary,
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
      ),
      for (final entry in results.entries)
        if (entry.value.forecast.length == length)
          LineChartBarData(
            spots: [
              for (int i = 0; i < length; i++)
                FlSpot(i.toDouble(), entry.value.forecast[i]),
            ],
            isCurved: true,
            color: _algoColors[entry.key] ?? AppColors.accent,
            barWidth: 2,
            dashArray: const [6, 4],
            dotData: const FlDotData(show: false),
          ),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.md,
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Actual vs. Forecast', style: AppTextStyles.h3),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true),
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 36),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 22),
                    ),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(
                      show: true,
                      border: Border.all(color: AppColors.border)),
                  lineBarsData: lines,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _legendDot(AppColors.textPrimary, 'Actual'),
                for (final key in results.keys)
                  _legendDot(_algoColors[key] ?? AppColors.accent, key),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(2),
        )),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.bodySmall),
      ],
    );
  }

  Widget _bestBanner(String key, ForecastResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: AppRadius.md,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Best algorithm: ${_algoLabel(key)}',
                    style: AppTextStyles.h3),
                const SizedBox(height: 2),
                Text(
                  'Lowest MAPE = ${(result.mape! * 100).toStringAsFixed(1)}% · Next-period forecast: ${result.nextPeriodForecast.toStringAsFixed(1)}',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
