import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/models/forecast_result.dart';
import 'package:ma5zony/services/settings_service.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class ForecastsScreen extends StatefulWidget {
  const ForecastsScreen({super.key});

  @override
  State<ForecastsScreen> createState() => _ForecastsScreenState();
}

class _ForecastsScreenState extends State<ForecastsScreen> {
  String? _selectedProductId;
  String? _algorithm;
  double? _smaWindow;
  double? _sesAlpha;
  bool _running = false;
  bool _defaultsLoaded = false;

  void _loadDefaults(UserSettings s) {
    if (_defaultsLoaded) return;
    _algorithm = s.defaultAlgorithm;
    _smaWindow = s.smaWindow.toDouble();
    _sesAlpha = s.sesAlpha;
    _defaultsLoaded = true;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _loadDefaults(state.settings);
    final products = state.products;
    final ForecastResult? forecast = state.currentForecast;

    if (_selectedProductId == null && products.isNotEmpty) {
      _selectedProductId = products.first.id;
    }

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Derived KPI values from ForecastResult
    final double mapePercent = forecast != null && forecast.mape != null
        ? forecast.mape! * 100
        : 0;
    final double accuracyPercent = forecast != null && forecast.mape != null
        ? (1 - forecast.mape!) * 100
        : 0;
    final int nextPeriod = forecast != null
        ? forecast.nextPeriodForecast.round()
        : 0;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Panel: Controls
          SizedBox(
            width: 300,
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Configuration', style: AppTextStyles.h3),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_selectedProductId),
                      initialValue: _selectedProductId,
                      decoration: const InputDecoration(
                        labelText: 'Target Product',
                        border: OutlineInputBorder(),
                      ),
                      items: products
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(
                                p.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedProductId = v),
                    ),
                    const SizedBox(height: 24),
                    const Text('Algorithm'),
                    const SizedBox(height: 8),
                    ToggleButtons(
                      isSelected: [_algorithm == 'SMA', _algorithm == 'SES'],
                      onPressed: (i) =>
                          setState(() => _algorithm = i == 0 ? 'SMA' : 'SES'),
                      borderRadius: BorderRadius.circular(8),
                      selectedColor: Colors.white,
                      fillColor: AppColors.primary,
                      color: AppColors.textSecondary,
                      constraints: const BoxConstraints(
                        minHeight: 40,
                        minWidth: 80,
                      ),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('SMA'),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('SES'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_algorithm == 'SMA') ...[
                      Text('Window Size: ${_smaWindow?.toInt() ?? 3} months'),
                      Slider(
                        value: _smaWindow ?? 3,
                        min: 2,
                        max: 12,
                        divisions: 10,
                        onChanged: (v) => setState(() => _smaWindow = v),
                      ),
                    ] else ...[
                      Text('Alpha: ${(_sesAlpha ?? 0.3).toStringAsFixed(2)}'),
                      Slider(
                        value: _sesAlpha ?? 0.3,
                        min: 0.1,
                        max: 0.9,
                        divisions: 8,
                        onChanged: (v) => setState(() => _sesAlpha = v),
                      ),
                    ],
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _running || _selectedProductId == null
                            ? null
                            : () async {
                                setState(() => _running = true);
                                await context.read<AppState>().runForecast(
                                  _selectedProductId!,
                                  _algorithm ?? 'SMA',
                                  (_smaWindow ?? 3).toInt(),
                                  _sesAlpha ?? 0.3,
                                );
                                setState(() => _running = false);
                              },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: _running
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Run Forecast'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 24),

          // Right Panel: Results
          Expanded(
            child: forecast == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.auto_graph,
                          size: 64,
                          color: AppColors.border,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Select a product and run a forecast',
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        // KPI chips
                        Row(
                          children: [
                            Expanded(
                              child: KPICard(
                                title: 'Forecast Accuracy',
                                value: '${accuracyPercent.toStringAsFixed(1)}%',
                                icon: Icons.check_circle,
                                color: AppColors.success,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: KPICard(
                                title: 'MAPE',
                                value: '${mapePercent.toStringAsFixed(1)}%',
                                icon: Icons.functions,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: KPICard(
                                title: 'Next Period Forecast',
                                value: '$nextPeriod',
                                icon: Icons.next_plan,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Lead-time KPI chips (shown when lead time data exists)
                        if (forecast.leadTimeDays != null &&
                            forecast.leadTimeDays! > 0)
                          Row(
                            children: [
                              Expanded(
                                child: KPICard(
                                  title: 'Lead Time',
                                  value: '${forecast.leadTimeDays} days',
                                  icon: Icons.schedule,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: KPICard(
                                  title: 'Demand During LT',
                                  value: forecast.demandDuringLeadTime
                                          ?.toStringAsFixed(0) ??
                                      '-',
                                  icon: Icons.trending_up,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: KPICard(
                                  title: 'Safety Stock',
                                  value:
                                      '${forecast.safetyStockForecast ?? '-'}',
                                  icon: Icons.shield,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: KPICard(
                                  title: 'Reorder Point',
                                  value:
                                      '${forecast.reorderPointForecast ?? '-'}',
                                  icon: Icons.notification_important,
                                  color: AppColors.warning,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 24),

                        // Chart
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Demand vs Forecast',
                                      style: AppTextStyles.h3,
                                    ),
                                    const Spacer(),
                                    _LegendDot(
                                      color: AppColors.textSecondary,
                                      label: 'Actual',
                                    ),
                                    const SizedBox(width: 12),
                                    _LegendDot(
                                      color: AppColors.primary,
                                      label: 'Forecast',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  height: 300,
                                  child: _ForecastLineChart(forecast: forecast),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Table
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Period')),
                                DataColumn(label: Text('Actual Demand')),
                                DataColumn(label: Text('Forecast')),
                                DataColumn(label: Text('Error')),
                              ],
                              rows: forecast.periods
                                  .asMap()
                                  .entries
                                  .take(forecast.periods.length)
                                  .map((e) {
                                    final actual = forecast.actualDemand[e.key];
                                    final fc = forecast.forecast[e.key];
                                    final error = actual > 0 && fc > 0
                                        ? (actual - fc).abs()
                                        : 0.0;
                                    return DataRow(
                                      cells: [
                                        DataCell(
                                          Text(
                                            DateFormat(
                                              'MMM yyyy',
                                            ).format(e.value),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            actual > 0
                                                ? actual.toStringAsFixed(0)
                                                : '-',
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            fc > 0
                                                ? fc.toStringAsFixed(0)
                                                : '-',
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            error > 0
                                                ? error.toStringAsFixed(1)
                                                : '-',
                                          ),
                                        ),
                                      ],
                                    );
                                  })
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ForecastLineChart extends StatelessWidget {
  final ForecastResult forecast;
  const _ForecastLineChart({required this.forecast});

  @override
  Widget build(BuildContext context) {
    final actualSpots = forecast.actualDemand
        .asMap()
        .entries
        .where((e) => e.value > 0)
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    final forecastSpots = forecast.forecast
        .asMap()
        .entries
        .where((e) => e.value > 0)
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return LineChart(
      LineChartData(
        lineBarsData: [
          if (actualSpots.isNotEmpty)
            LineChartBarData(
              spots: actualSpots,
              color: AppColors.textSecondary,
              barWidth: 2,
              dotData: const FlDotData(show: true),
            ),
          if (forecastSpots.isNotEmpty)
            LineChartBarData(
              spots: forecastSpots,
              color: AppColors.primary,
              barWidth: 3,
              isCurved: true,
              dashArray: [5, 5],
              dotData: const FlDotData(show: false),
            ),
        ],
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: AppColors.border),
        ),
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppColors.border, strokeWidth: 0.5),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.label),
      ],
    );
  }
}
