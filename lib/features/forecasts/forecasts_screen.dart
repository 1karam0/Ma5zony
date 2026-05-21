import 'package:csv/csv.dart' show CsvEncoder;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/features/forecasts/algorithm_breakdown_panel.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/replenishment_recommendation.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/models/forecast_result.dart';
import 'package:ma5zony/services/settings_service.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/utils/download_helper.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

// ── Algorithm metadata ──────────────────────────────────────────────────────

const _algorithms = [
  _AlgoMeta(
    code: 'SMA',
    label: 'SMA',
    fullName: 'Simple Moving Average',
    icon: Icons.show_chart,
    description: 'Average of last N periods. Best for stable, non-seasonal demand.',
  ),
  _AlgoMeta(
    code: 'WMA',
    label: 'WMA',
    fullName: 'Weighted Moving Average',
    icon: Icons.bar_chart,
    description: 'Like SMA but recent periods get higher weight. More reactive.',
  ),
  _AlgoMeta(
    code: 'SES',
    label: 'SES',
    fullName: 'Single Exponential Smoothing',
    icon: Icons.timeline,
    description: 'Continuous weighting via alpha (α). Great for short-term forecasting.',
  ),
  _AlgoMeta(
    code: 'Holt',
    label: 'Holt',
    fullName: "Holt's Double Exponential",
    icon: Icons.trending_up,
    description: 'Captures level + trend. Use when demand grows or declines steadily.',
  ),
  _AlgoMeta(
    code: 'HoltWinters',
    label: 'H-W',
    fullName: 'Holt-Winters Triple Exponential',
    icon: Icons.auto_graph,
    description: 'Level + trend + seasonality. Best for cyclic demand patterns (needs ≥12 data points).',
  ),
];

class _AlgoMeta {
  final String code;
  final String label;
  final String fullName;
  final IconData icon;
  final String description;
  const _AlgoMeta({
    required this.code,
    required this.label,
    required this.fullName,
    required this.icon,
    required this.description,
  });
}

// ── Screen ──────────────────────────────────────────────────────────────────

class ForecastsScreen extends StatefulWidget {
  final String? preSelectedProductId;
  const ForecastsScreen({super.key, this.preSelectedProductId});

  @override
  State<ForecastsScreen> createState() => _ForecastsScreenState();
}

class _ForecastsScreenState extends State<ForecastsScreen> {
  String? _selectedProductId;
  String _algorithm = 'SMA';
  double _smaWindow = 3;
  int _wmaWeightCount = 3;
  double _alpha = 0.3;
  double _beta = 0.1;
  double _gamma = 0.2;
  int _seasonLength = 12;
  bool _running = false;
  bool _defaultsLoaded = false;
  bool _autoRanForPreSelected = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_defaultsLoaded) {
      final state = context.read<AppState>();
      _loadDefaults(state.settings);
      if (widget.preSelectedProductId != null) {
        _selectedProductId = widget.preSelectedProductId;
      } else if (_selectedProductId == null && state.products.isNotEmpty) {
        _selectedProductId = state.products.first.id;
      }
      // Deep-link arrival: try to rehydrate the most recently persisted
      // forecast first; only auto-run a fresh forecast if none is cached.
      if (widget.preSelectedProductId != null && !_autoRanForPreSelected) {
        _autoRanForPreSelected = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final loaded = await context
              .read<AppState>()
              .loadLatestForecast(widget.preSelectedProductId!);
          if (!mounted) return;
          if (!loaded) _runForecast();
        });
      }
    } else if (_selectedProductId == null) {
      final products = context.read<AppState>().products;
      if (products.isNotEmpty) {
        _selectedProductId = products.first.id;
      }
    }
  }

  void _loadDefaults(UserSettings s) {
    if (_defaultsLoaded) return;
    _algorithm = s.defaultAlgorithm;
    _smaWindow = s.smaWindow.toDouble();
    _alpha = s.sesAlpha;
    _beta = s.holtBeta;
    _gamma = s.holtGamma;
    _seasonLength = s.holtWintersSeasonLength;
    _defaultsLoaded = true;
  }

  List<double> get _wmaWeights {
    // Linear weights: [1, 2, 3, ...n] (most recent = highest)
    return List.generate(_wmaWeightCount, (i) => (i + 1).toDouble());
  }

  Future<void> _runForecast() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _running = true);
    try {
      await context.read<AppState>().runForecast(
        _selectedProductId!,
        _algorithm,
        _smaWindow.toInt(),
        _alpha,
        beta: _beta,
        gamma: _gamma,
        wmaWeights: _wmaWeights,
        seasonLength: _seasonLength,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Forecast timed out. Ensure this product has demand data.'),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Forecast failed: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(label: 'Dismiss', textColor: Colors.white, onPressed: () {}),
        ));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final products = state.products;
    final ForecastResult? forecast = state.currentForecast;

    if (state.isLoading) return const Center(child: CircularProgressIndicator());

    // Sync product selection when products load (safe: no setState during build)
    final algoMeta = _algorithms.firstWhere((a) => a.code == _algorithm, orElse: () => _algorithms.first);

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.query_stats), text: 'Demand Forecast'),
                Tab(icon: Icon(Icons.shopping_cart_outlined), text: 'Replenishment & Orders'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // ── Tab 1: Demand Forecast ──────────────────────────
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HelpBanner(
                        hasProducts: products.isNotEmpty,
                        hasForecast: forecast != null,
                        algorithm: _algorithm,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Left Panel: Controls ──
                          SizedBox(
                            width: 320,
                            child: Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Configuration', style: AppTextStyles.h3),
                                    const SizedBox(height: 20),
                                    InputDecorator(
                                      decoration: const InputDecoration(
                                        labelText: 'Target Product',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.inventory_2_outlined),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedProductId,
                                          isExpanded: true,
                                          isDense: true,
                                          hint: const Text('Select product', style: TextStyle(fontSize: 14)),
                                          items: products
                                              .map((p) => DropdownMenuItem(
                                                    value: p.id,
                                                    child: Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                                                  ))
                                              .toList(),
                                          onChanged: (v) {
                                            setState(() => _selectedProductId = v);
                                            context.read<AppState>().clearCurrentForecast();
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Text('Forecasting Algorithm', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 10),
                                    _AlgorithmSelector(
                                      selected: _algorithm,
                                      onChanged: (v) => setState(() => _algorithm = v),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLight,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(algoMeta.icon, size: 14, color: AppColors.primary),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              algoMeta.description,
                                              style: AppTextStyles.bodySmall.copyWith(
                                                color: AppColors.primary,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    _AlgorithmParams(
                                      algorithm: _algorithm,
                                      smaWindow: _smaWindow,
                                      wmaWeightCount: _wmaWeightCount,
                                      alpha: _alpha,
                                      beta: _beta,
                                      gamma: _gamma,
                                      seasonLength: _seasonLength,
                                      onSmaWindowChanged: (v) => setState(() => _smaWindow = v),
                                      onWmaWeightCountChanged: (v) => setState(() => _wmaWeightCount = v),
                                      onAlphaChanged: (v) => setState(() => _alpha = v),
                                      onBetaChanged: (v) => setState(() => _beta = v),
                                      onGammaChanged: (v) => setState(() => _gamma = v),
                                      onSeasonLengthChanged: (v) => setState(() => _seasonLength = v),
                                    ),
                                    const SizedBox(height: 28),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _running || _selectedProductId == null ? null : _runForecast,
                                        icon: _running
                                            ? const SizedBox(
                                                width: 16, height: 16,
                                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                              )
                                            : const Icon(Icons.play_arrow),
                                        label: Text(_running ? 'Running…' : 'Run Forecast'),
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          // ── Right Panel: Results ──
                          Expanded(
                            child: forecast == null
                                ? SizedBox(
                                    height: 420,
                                    child: Center(child: _EmptyState(hasProducts: products.isNotEmpty)),
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Urgent stock context card when deep-linked
                                      if (widget.preSelectedProductId != null && _selectedProductId != null)
                                        _UrgentStockContextCard(
                                          productId: _selectedProductId!,
                                          state: state,
                                        ),
                                      if (widget.preSelectedProductId != null)
                                        const SizedBox(height: 12),
                                      _ForecastKpiRow(forecast: forecast),
                                      const SizedBox(height: 16),
                                      if (forecast.leadTimeDays != null && forecast.leadTimeDays! > 0)
                                        _LeadTimeKpiRow(forecast: forecast),
                                      if (forecast.leadTimeDays != null && forecast.leadTimeDays! > 0)
                                        const SizedBox(height: 16),
                                      _ForecastChartCard(forecast: forecast),
                                      const SizedBox(height: 20),
                                      // Lead time detail card
                                      if (_selectedProductId != null)
                                        _LeadTimeSummaryCard(
                                          productId: _selectedProductId!,
                                          state: state,
                                        ),
                                      const SizedBox(height: 20),
                                      AlgorithmBreakdownPanel(result: forecast),
                                      const SizedBox(height: 20),
                                      _InventoryPolicyPanel(
                                        forecast: forecast,
                                        settings: context.read<AppState>().settings,
                                        selectedProductId: _selectedProductId,
                                        state: context.read<AppState>(),
                                      ),
                                      const SizedBox(height: 20),
                                      _ForecastDataTable(forecast: forecast),
                                      // RM Order CTA
                                      if (_selectedProductId != null &&
                                          state.boms.any((b) =>
                                              b.finalProductId == _selectedProductId && b.isActive))
                                        _RmOrderCta(
                                          productId: _selectedProductId!,
                                          forecastQty: forecast.nextPeriodForecast,
                                          state: state,
                                        ),
                                      const SizedBox(height: 24),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Tab 2: Replenishment & Orders ───────────────────
                const _ReplenishmentTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Algorithm Selector Grid ─────────────────────────────────────────────────

class _AlgorithmSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _AlgorithmSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _algorithms.map((algo) {
        final isSelected = selected == algo.code;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Tooltip(
            message: algo.description,
            preferBelow: false,
            child: InkWell(
              onTap: () => onChanged(algo.code),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      algo.icon,
                      size: 16,
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      algo.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isSelected ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        algo.fullName,
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.85)
                              : AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle, size: 14, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Algorithm Parameters ────────────────────────────────────────────────────

class _AlgorithmParams extends StatelessWidget {
  final String algorithm;
  final double smaWindow;
  final int wmaWeightCount;
  final double alpha;
  final double beta;
  final double gamma;
  final int seasonLength;
  final ValueChanged<double> onSmaWindowChanged;
  final ValueChanged<int> onWmaWeightCountChanged;
  final ValueChanged<double> onAlphaChanged;
  final ValueChanged<double> onBetaChanged;
  final ValueChanged<double> onGammaChanged;
  final ValueChanged<int> onSeasonLengthChanged;

  const _AlgorithmParams({
    required this.algorithm,
    required this.smaWindow,
    required this.wmaWeightCount,
    required this.alpha,
    required this.beta,
    required this.gamma,
    required this.seasonLength,
    required this.onSmaWindowChanged,
    required this.onWmaWeightCountChanged,
    required this.onAlphaChanged,
    required this.onBetaChanged,
    required this.onGammaChanged,
    required this.onSeasonLengthChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Parameters', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        if (algorithm == 'SMA') ...[
          _ParamSlider(
            label: 'Window size (n)',
            value: smaWindow,
            min: 2, max: 12, step: 1,
            display: '${smaWindow.toInt()} months',
            formula: 'F = avg(last n periods)',
            onChanged: onSmaWindowChanged,
          ),
        ] else if (algorithm == 'WMA') ...[
          _ParamSlider(
            label: 'Number of periods',
            value: wmaWeightCount.toDouble(),
            min: 2, max: 8, step: 1,
            display: '$wmaWeightCount periods',
            formula: 'Weights: ${List.generate(wmaWeightCount, (i) => i + 1).join(', ')} (linear)',
            onChanged: (v) => onWmaWeightCountChanged(v.toInt()),
          ),
        ] else if (algorithm == 'SES') ...[
          _ParamSlider(
            label: 'Alpha (α) — smoothing',
            value: alpha,
            min: 0.05, max: 0.95, step: 0.05,
            display: alpha.toStringAsFixed(2),
            formula: 'Higher α = more weight on recent demand',
            onChanged: onAlphaChanged,
          ),
        ] else if (algorithm == 'Holt') ...[
          _ParamSlider(
            label: 'Alpha (α) — level',
            value: alpha,
            min: 0.05, max: 0.95, step: 0.05,
            display: alpha.toStringAsFixed(2),
            formula: 'Controls how fast the level adapts',
            onChanged: onAlphaChanged,
          ),
          const SizedBox(height: 10),
          _ParamSlider(
            label: 'Beta (β) — trend',
            value: beta,
            min: 0.01, max: 0.50, step: 0.01,
            display: beta.toStringAsFixed(2),
            formula: 'Controls how fast the trend adapts',
            onChanged: onBetaChanged,
          ),
        ] else if (algorithm == 'HoltWinters') ...[
          _ParamSlider(
            label: 'Alpha (α) — level',
            value: alpha,
            min: 0.05, max: 0.95, step: 0.05,
            display: alpha.toStringAsFixed(2),
            formula: 'Smoothing for the level component',
            onChanged: onAlphaChanged,
          ),
          const SizedBox(height: 10),
          _ParamSlider(
            label: 'Beta (β) — trend',
            value: beta,
            min: 0.01, max: 0.50, step: 0.01,
            display: beta.toStringAsFixed(2),
            formula: 'Smoothing for the trend component',
            onChanged: onBetaChanged,
          ),
          const SizedBox(height: 10),
          _ParamSlider(
            label: 'Gamma (γ) — seasonal',
            value: gamma,
            min: 0.01, max: 0.50, step: 0.01,
            display: gamma.toStringAsFixed(2),
            formula: 'Smoothing for the seasonal component',
            onChanged: onGammaChanged,
          ),
          const SizedBox(height: 10),
          _ParamSlider(
            label: 'Season length (s)',
            value: seasonLength.toDouble(),
            min: 4, max: 24, step: 1,
            display: '$seasonLength periods',
            formula: 'Needs ≥$seasonLength data points',
            onChanged: (v) => onSeasonLengthChanged(v.toInt()),
          ),
        ],
      ],
    );
  }
}

class _ParamSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String display;
  final String formula;
  final ValueChanged<double> onChanged;

  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.display,
    required this.formula,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final progress = max > min ? ((value - min) / (max - min)).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(label, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(display, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StepBtn(
                icon: Icons.remove,
                enabled: value > min,
                onPressed: () => onChanged((value - step).clamp(min, max)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: AppColors.borderLight,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                ),
              ),
              _StepBtn(
                icon: Icons.add,
                enabled: value < max,
                onPressed: () => onChanged((value + step).clamp(min, max)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(formula, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSubdued, fontSize: 10)),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  const _StepBtn({required this.icon, required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: enabled ? AppColors.primary.withValues(alpha: 0.1) : AppColors.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: enabled ? AppColors.primary.withValues(alpha: 0.4) : AppColors.borderLight,
          ),
        ),
        child: Icon(icon, size: 16, color: enabled ? AppColors.primary : AppColors.textSubdued),
      ),
    );
  }
}

// ── KPI Rows ────────────────────────────────────────────────────────────────

class _ForecastKpiRow extends StatelessWidget {
  final ForecastResult forecast;
  const _ForecastKpiRow({required this.forecast});

  @override
  Widget build(BuildContext context) {
    final mape = forecast.mape != null ? forecast.mape! * 100 : 0.0;
    final accuracy = forecast.mape != null ? (1 - forecast.mape!) * 100 : 0.0;
    final nextPeriod = forecast.nextPeriodForecast.round();

    return Row(
      children: [
        Expanded(
          child: KPICard(
            title: 'Forecast Accuracy',
            value: '${accuracy.toStringAsFixed(1)}%',
            icon: Icons.verified,
            color: accuracy >= 90 ? AppColors.success : (accuracy >= 75 ? AppColors.warning : AppColors.error),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: KPICard(
            title: 'MAPE',
            value: mape == 0 ? '-' : '${mape.toStringAsFixed(1)}%',
            icon: Icons.functions,
            color: mape == 0
                ? AppColors.textSecondary
                : (mape < 10 ? AppColors.success : (mape < 20 ? AppColors.warning : AppColors.error)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: KPICard(
            title: 'Next Period',
            value: '$nextPeriod units',
            icon: Icons.next_plan,
            color: AppColors.primary,
          ),
        ),
        if (forecast.rmse != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: KPICard(
              title: 'RMSE',
              value: forecast.rmse!.toStringAsFixed(1),
              icon: Icons.analytics_outlined,
              color: AppColors.info,
            ),
          ),
        ],
      ],
    );
  }
}

class _LeadTimeKpiRow extends StatelessWidget {
  final ForecastResult forecast;
  const _LeadTimeKpiRow({required this.forecast});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: KPICard(
            title: 'Lead Time',
            value: '${forecast.leadTimeDays} days',
            icon: Icons.schedule,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: KPICard(
            title: 'Demand During LT',
            value: forecast.demandDuringLeadTime?.toStringAsFixed(0) ?? '-',
            icon: Icons.trending_up,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: KPICard(
            title: 'Safety Stock',
            value: '${forecast.safetyStockForecast ?? '-'} units',
            icon: Icons.shield,
            color: AppColors.info,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: KPICard(
            title: 'Reorder Point',
            value: '${forecast.reorderPointForecast ?? '-'} units',
            icon: Icons.notification_important,
            color: AppColors.warning,
          ),
        ),
      ],
    );
  }
}

// ── Chart Card ──────────────────────────────────────────────────────────────

class _ForecastChartCard extends StatelessWidget {
  final ForecastResult forecast;
  const _ForecastChartCard({required this.forecast});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Demand vs Forecast', style: AppTextStyles.h3),
                const Spacer(),
                _LegendDot(color: AppColors.textSecondary, label: 'Actual'),
                const SizedBox(width: 12),
                _LegendDot(color: AppColors.primary, label: 'Forecast'),
                if (forecast.confidenceUpper != null) ...[
                  const SizedBox(width: 12),
                  _LegendDot(color: AppColors.primary.withValues(alpha: 0.3), label: '95% CI'),
                ],
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 280,
              child: _ForecastLineChart(forecast: forecast),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Inventory Policy Panel ──────────────────────────────────────────────────

class _InventoryPolicyPanel extends StatelessWidget {
  final ForecastResult forecast;
  final UserSettings settings;
  final String? selectedProductId;
  final AppState state;

  const _InventoryPolicyPanel({
    required this.forecast,
    required this.settings,
    required this.selectedProductId,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    // Pull product + demand data
    final product = selectedProductId != null
        ? state.products.where((p) => p.id == selectedProductId).firstOrNull
        : null;

    if (product == null) return const SizedBox.shrink();

    final unitCost = product.unitCost;
    final orderingCost = settings.orderingCost;
    final holdingRate = settings.holdingRate;
    final holdingCostPerUnit = unitCost * holdingRate;

    // Annual demand from forecast next period × 12
    final monthlyDemand = forecast.nextPeriodForecast;
    final annualDemand = monthlyDemand * 12;

    // EOQ = √(2DS/H)
    final eoq = holdingCostPerUnit > 0 && annualDemand > 0
        ? (2 * annualDemand * orderingCost / holdingCostPerUnit)
        : 0.0;
    final eoqRounded = eoq > 0 ? eoq.ceil() : 0;

    final safetyStock = forecast.safetyStockForecast ?? 0;
    final rop = forecast.reorderPointForecast ?? 0;

    final serviceLevelZ = settings.serviceLevelTarget == 99
        ? 2.33
        : settings.serviceLevelTarget == 97
            ? 1.96
            : 1.65;
    final serviceLevelLabel = '${settings.serviceLevelTarget.toInt()}%';

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
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
          leading: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.calculate, color: AppColors.warning, size: 20),
          ),
          title: Text('Inventory Policy (EOQ / Safety Stock / ROP)', style: AppTextStyles.h3),
          subtitle: Text(
            'Based on forecast → formulae from Silver, Pyke & Peterson',
            style: AppTextStyles.bodySmall,
          ),
          children: [
            const Divider(),
            const SizedBox(height: 16),

            // Three formula cards in a row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _FormulaResultCard(
                    icon: Icons.shopping_cart,
                    color: AppColors.success,
                    title: 'EOQ',
                    subtitle: 'Economic Order Quantity',
                    formula: 'EOQ = √(2 × D × S / H)',
                    substituted:
                        'EOQ = √(2 × ${annualDemand.toStringAsFixed(0)} × ${orderingCost.toStringAsFixed(0)} / ${holdingCostPerUnit.toStringAsFixed(2)})',
                    result: '$eoqRounded units',
                    explanation: 'Order this quantity each time to minimise total ordering + holding cost.',
                    variables: [
                      ('D', 'Annual demand', '${annualDemand.toStringAsFixed(0)} units/yr'),
                      ('S', 'Ordering cost', 'EGP ${orderingCost.toStringAsFixed(0)}/order'),
                      ('H', 'Holding cost', 'EGP ${holdingCostPerUnit.toStringAsFixed(2)}/unit/yr'),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FormulaResultCard(
                    icon: Icons.shield,
                    color: AppColors.info,
                    title: 'Safety Stock',
                    subtitle: 'Buffer for demand variability',
                    formula: 'SS = Z × σ × √(LT)',
                    substituted:
                        'SS = ${serviceLevelZ.toStringAsFixed(2)} × σ × √(LT)',
                    result: '$safetyStock units',
                    explanation: 'Keep this buffer on hand to meet demand during unexpected delays.',
                    variables: [
                      ('Z', 'Service level z-score', '${serviceLevelZ.toStringAsFixed(2)} ($serviceLevelLabel SL)'),
                      ('σ', 'Demand std deviation', 'from history'),
                      ('LT', 'Lead time in periods', '${(forecast.leadTimeDays ?? 0) ~/ 30} months'),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FormulaResultCard(
                    icon: Icons.notification_important,
                    color: AppColors.warning,
                    title: 'Reorder Point',
                    subtitle: 'Trigger order when stock hits this',
                    formula: 'ROP = (D × LT) + SS',
                    substituted:
                        'ROP = (${monthlyDemand.toStringAsFixed(1)} × ${(forecast.leadTimeDays ?? 0) ~/ 30}) + $safetyStock',
                    result: '$rop units',
                    explanation: 'Place a new order when your stock level reaches this point.',
                    variables: [
                      ('D', 'Monthly demand forecast', '${monthlyDemand.toStringAsFixed(1)} units'),
                      ('LT', 'Lead time', '${(forecast.leadTimeDays ?? 0) ~/ 30} months'),
                      ('SS', 'Safety stock', '$safetyStock units'),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Settings note
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: AppRadius.sm,
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 14, color: AppColors.textSubdued),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Parameters: Ordering cost = EGP ${orderingCost.toStringAsFixed(0)}/order  •  '
                      'Holding rate = ${(holdingRate * 100).toStringAsFixed(0)}% of unit cost  •  '
                      'Unit cost = EGP ${unitCost.toStringAsFixed(2)}  •  '
                      'Service level = $serviceLevelLabel  •  '
                      'Adjust in Settings → Global Parameters',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSubdued,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _FormulaResultCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String formula;
  final String substituted;
  final String result;
  final String explanation;
  final List<(String, String, String)> variables;

  const _FormulaResultCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.formula,
    required this.substituted,
    required this.result,
    required this.explanation,
    required this.variables,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: AppRadius.sm,
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(title, style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSubdued, fontSize: 10)),
          const SizedBox(height: 10),

          // Formula
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formula,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(substituted,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: color.withValues(alpha: 0.8))),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Result
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              result,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 10),

          // Variable table
          ...variables.map((v) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(v.$1,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: color)),
                ),
                Text(' = ', style: AppTextStyles.bodySmall.copyWith(fontSize: 10)),
                Expanded(
                  child: Text('${v.$2}: ${v.$3}',
                      style: AppTextStyles.bodySmall.copyWith(fontSize: 10)),
                ),
              ],
            ),
          )),

          const SizedBox(height: 6),
          Text(explanation,
              style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSubdued, fontSize: 10, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

// ── Data Table ──────────────────────────────────────────────────────────────

class _ForecastDataTable extends StatelessWidget {
  final ForecastResult forecast;
  const _ForecastDataTable({required this.forecast});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: HorizontallyScrollableTable(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.background),
          columns: const [
            DataColumn(label: Text('Period')),
            DataColumn(label: Text('Actual Demand'), numeric: true),
            DataColumn(label: Text('Forecast'), numeric: true),
            DataColumn(label: Text('Error'), numeric: true),
            DataColumn(label: Text('Error %'), numeric: true),
          ],
          rows: forecast.periods.asMap().entries.map((e) {
            final i = e.key;
            final actual = forecast.actualDemand[i];
            final fc = forecast.forecast[i];
            final isForecastPeriod = actual <= 0;
            final absError = actual > 0 && fc > 0 ? (actual - fc).abs() : 0.0;
            final pctError = actual > 0 ? (absError / actual * 100) : 0.0;

            return DataRow(
              color: isForecastPeriod
                  ? WidgetStateProperty.all(AppColors.primaryLight)
                  : null,
              cells: [
                DataCell(Row(children: [
                  Text(DateFormat('MMM yyyy').format(e.value)),
                  if (isForecastPeriod)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('forecast', style: TextStyle(color: Colors.white, fontSize: 9)),
                    ),
                ])),
                DataCell(Text(actual > 0 ? actual.toStringAsFixed(0) : '—')),
                DataCell(Text(
                  fc > 0 ? fc.toStringAsFixed(1) : '—',
                  style: isForecastPeriod
                      ? const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary)
                      : null,
                )),
                DataCell(Text(absError > 0 ? absError.toStringAsFixed(1) : '—')),
                DataCell(Text(
                  pctError > 0 ? '${pctError.toStringAsFixed(1)}%' : '—',
                  style: TextStyle(
                    color: pctError > 20
                        ? AppColors.error
                        : pctError > 10
                            ? AppColors.warning
                            : AppColors.textPrimary,
                  ),
                )),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Help Banner ─────────────────────────────────────────────────────────────

class _HelpBanner extends StatelessWidget {
  final bool hasProducts;
  final bool hasForecast;
  final String algorithm;
  const _HelpBanner({required this.hasProducts, required this.hasForecast, required this.algorithm});

  @override
  Widget build(BuildContext context) {
    final algoMeta = _algorithms.firstWhere((a) => a.code == algorithm, orElse: () => _algorithms.first);
    final color = hasForecast ? AppColors.success : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(hasForecast ? Icons.check_circle : algoMeta.icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasForecast
                      ? 'Forecast complete — ${algoMeta.fullName}'
                      : (hasProducts ? 'Select an algorithm, tune parameters, then click Run Forecast' : 'Add or import products first to enable forecasting.'),
                  style: AppTextStyles.body.copyWith(color: color, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                if (hasForecast)
                  Text(
                    algoMeta.description,
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          if (hasForecast)
            TextButton.icon(
              onPressed: () => context.go('/forecasts/compare'),
              icon: const Icon(Icons.compare_arrows, size: 14),
              label: const Text('Compare All'),
              style: TextButton.styleFrom(foregroundColor: color, textStyle: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

// ── Empty State ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasProducts;
  const _EmptyState({required this.hasProducts});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(hasProducts ? Icons.auto_graph : Icons.inventory_2_outlined,
              size: 64, color: AppColors.border),
          const SizedBox(height: 16),
          Text(
            hasProducts ? 'Select a product and run a forecast' : 'Add products to enable forecasting',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          if (hasProducts) ...[
            const SizedBox(height: 8),
            Text(
              'Choose an algorithm from the left panel,\ntune the parameters, then click Run Forecast',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSubdued),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Line Chart ──────────────────────────────────────────────────────────────

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

    final upperSpots = forecast.confidenceUpper
        ?.asMap()
        .entries
        .where((e) => e.value > 0)
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    final lowerSpots = forecast.confidenceLower
        ?.asMap()
        .entries
        .where((e) => e.value > 0)
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    final bars = <LineChartBarData>[];

    if (upperSpots != null && upperSpots.isNotEmpty) {
      bars.add(LineChartBarData(
        spots: upperSpots,
        color: AppColors.primary.withValues(alpha: 0.25),
        barWidth: 1,
        dotData: const FlDotData(show: false),
        dashArray: [3, 3],
      ));
    }

    if (lowerSpots != null && lowerSpots.isNotEmpty) {
      bars.add(LineChartBarData(
        spots: lowerSpots,
        color: AppColors.primary.withValues(alpha: 0.25),
        barWidth: 1,
        dotData: const FlDotData(show: false),
        dashArray: [3, 3],
      ));
    }

    if (actualSpots.isNotEmpty) {
      bars.add(LineChartBarData(
        spots: actualSpots,
        color: AppColors.textSecondary,
        barWidth: 2,
        dotData: const FlDotData(show: true),
      ));
    }

    if (forecastSpots.isNotEmpty) {
      bars.add(LineChartBarData(
        spots: forecastSpots,
        color: AppColors.primary,
        barWidth: 3,
        isCurved: true,
        dashArray: [5, 5],
        dotData: const FlDotData(show: false),
      ));
    }

    return LineChart(
      LineChartData(
        lineBarsData: bars,
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: AppColors.border),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.borderLight, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: (forecast.periods.length / 6).ceilToDouble(),
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= forecast.periods.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('MMM yy').format(forecast.periods[idx]),
                    style: const TextStyle(fontSize: 10, color: AppColors.textSubdued),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: const TextStyle(fontSize: 10, color: AppColors.textSubdued),
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
      ),
    );
  }
}

// ── Legend Dot ──────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.bodySmall),
      ],
    );
  }
}

// ── Replenishment & Orders Tab ───────────────────────────────────────────────

class _ReplenishmentTab extends StatefulWidget {
  const _ReplenishmentTab();

  @override
  State<_ReplenishmentTab> createState() => _ReplenishmentTabState();
}

class _ReplenishmentTabState extends State<_ReplenishmentTab> {
  String _searchQuery = '';
  final Map<String, int> _adjustedQty = {};
  final Set<String> _selectedIds = {};
  bool _selectAll = false;
  bool _sortByPriority = true;
  final Map<String, bool> _approving = {};
  bool _bulkApproving = false;

  void _exportCsv(
    BuildContext context,
    List<ReplenishmentRecommendation> recs,
    Map<String, Product> productMap,
  ) {
    final rows = <List<dynamic>>[
      ['Product', 'SKU', 'Stock', 'Forecast', 'ROP', 'Suggested Qty', 'Status'],
      ...recs.map((r) => [
            r.productName,
            r.sku,
            r.currentStock,
            r.forecastNextPeriod,
            r.reorderPoint,
            r.suggestedOrderQty,
            r.status,
          ]),
    ];
    final csvString = const CsvEncoder().convert(rows);

    if (kIsWeb) {
      downloadCsvWeb(csvString, 'replenishment_export.csv');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV downloaded')),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('CSV Export'),
          content: SingleChildScrollView(child: SelectableText(csvString)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildArrivalDate(
    ReplenishmentRecommendation r,
    Product? product,
    Map<String, Supplier> supplierMap,
  ) {
    if (product?.supplierId == null) {
      return const Text('—', style: TextStyle(color: Colors.grey));
    }
    final supplier = supplierMap[product!.supplierId!];
    if (supplier == null) {
      return const Text('—', style: TextStyle(color: Colors.grey));
    }
    final leadDays = supplier.typicalLeadTimeDays;
    final arrival = r.recommendedOrderDate.add(Duration(days: leadDays));
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(DateFormat('d MMM').format(arrival),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('+${leadDays}d', style: AppTextStyles.label),
      ],
    );
  }

  Widget _buildApproveButton(BuildContext context, ReplenishmentRecommendation r, Product? product) {
    final approved = context.watch<AppState>().approvedRecommendations;
    if (approved.contains(r.productId)) {
      return const Chip(
        label: Text('Approved', style: TextStyle(color: Colors.white, fontSize: 12)),
        backgroundColor: AppColors.success,
      );
    }
    final isManufacture = product?.manufacturerId != null && product!.manufacturerId!.isNotEmpty;
    final isApproving = _approving[r.productId] == true;
    return TextButton(
      onPressed: isApproving ? null : () => _approveSingle(context, r, isManufacture),
      child: isApproving
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(isManufacture ? 'Manufacture' : 'Approve'),
    );
  }

  Future<void> _approveSingle(
    BuildContext context,
    ReplenishmentRecommendation r,
    bool isManufacture,
  ) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = GoRouter.of(context);

    // For manufacture-type, show BOM confirmation dialog first.
    if (isManufacture) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _BomConfirmDialog(
          rec: r,
          adjustedQty: _adjustedQty[r.productId] ?? r.suggestedOrderQty,
          state: state,
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _approving[r.productId] = true);
    try {
      final adjustedRec = _adjustedQty.containsKey(r.productId)
          ? r.copyWith(suggestedOrderQty: _adjustedQty[r.productId])
          : r;

      if (isManufacture) {
        await state.approveReplenishmentManufacture(adjustedRec);
        final count = state.lastApprovalEmailsSent;
        final emailNote = count > 0
            ? ' — $count email${count == 1 ? '' : 's'} sent'
            : '';
        messenger.showSnackBar(SnackBar(
          content: Text('Production order created for ${r.productName}$emailNote'),
          backgroundColor: AppColors.success,
        ));
        navigator.go('/production-orders');
      } else {
        await state.approveRecommendation(adjustedRec);
        final count = state.lastApprovalEmailsSent;
        final emailNote = count > 0
            ? ' — $count email${count == 1 ? '' : 's'} sent'
            : ' (no supplier email on file)';
        messenger.showSnackBar(SnackBar(
          content: Text('${r.productName} approved$emailNote'),
          backgroundColor: AppColors.success,
        ));
        navigator.go('/orders');
      }
    } on CloudFunctionException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Order created but email delivery failed: ${e.message}'),
        backgroundColor: AppColors.warning,
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _approving.remove(r.productId));
    }
  }

  Future<void> _approveSelected(
    BuildContext context,
    List<ReplenishmentRecommendation> recs,
    Map<String, Product> productMap,
  ) async {
    setState(() => _bulkApproving = true);
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = GoRouter.of(context);
    int purchaseCount = 0;
    int mfgCount = 0;
    int emailsFailed = 0;
    try {
      for (final r in recs) {
        if (!_selectedIds.contains(r.productId)) continue;
        if (state.approvedRecommendations.contains(r.productId)) continue;
        final adjustedRec = _adjustedQty.containsKey(r.productId)
            ? r.copyWith(suggestedOrderQty: _adjustedQty[r.productId])
            : r;
        try {
          await state.approveRecommendation(adjustedRec);
        } on CloudFunctionException {
          emailsFailed++;
        }
        final product = productMap[r.productId];
        final isManufacture = product?.manufacturerId != null && product!.manufacturerId!.isNotEmpty;
        if (isManufacture) {
          mfgCount++;
        } else {
          purchaseCount++;
        }
      }
      if (!mounted) return;
      final parts = <String>[];
      if (purchaseCount > 0) parts.add('$purchaseCount purchase');
      if (mfgCount > 0) parts.add('$mfgCount manufacturing');
      final failNote = emailsFailed > 0
          ? ' ($emailsFailed email failure${emailsFailed == 1 ? '' : 's'})'
          : '';
      messenger.showSnackBar(SnackBar(
        content: Text('${parts.join(", ")} order(s) approved$failNote'),
        backgroundColor: emailsFailed > 0 ? AppColors.warning : AppColors.success,
      ));
      setState(() {
        _selectedIds.clear();
        _selectAll = false;
      });
      if (mfgCount > 0) {
        navigator.go('/recommendations');
      } else if (purchaseCount > 0) {
        navigator.go('/orders');
      }
    } finally {
      if (mounted) setState(() => _bulkApproving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final productMap = {for (final p in state.products) p.id: p};
    final cashFlow = state.latestCashFlow;

    final List<ReplenishmentRecommendation> recommendations = state.recommendations
        .where((r) {
          if (_searchQuery.isEmpty) return true;
          return r.productName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              r.sku.toLowerCase().contains(_searchQuery.toLowerCase());
        })
        .toList();

    if (_sortByPriority) {
      const priority = {'Critical': 0, 'Order Now': 1, 'Monitor': 2};
      recommendations.sort(
        (a, b) => (priority[a.status] ?? 3).compareTo(priority[b.status] ?? 3),
      );
    }

    final supplierMap = {for (final s in state.suppliers) s.id: s};

    final totalSuggested = recommendations.fold<int>(
      0, (s, r) => s + (_adjustedQty[r.productId] ?? r.suggestedOrderQty),
    );
    final needingAction = recommendations
        .where((r) => r.status == 'Critical' || r.status == 'Order Now')
        .length;
    final estimatedCost = recommendations.fold<double>(0, (sum, r) {
      final product = productMap[r.productId];
      final qty = _adjustedQty[r.productId] ?? r.suggestedOrderQty;
      return sum + qty * (product?.unitCost ?? 0);
    });

    if (state.isLoading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Budget constraint card
          if (cashFlow != null) ...[
            _BudgetCard(
              remainingBudget: cashFlow.remainingBudget,
              estimatedCost: estimatedCost,
            ),
            const SizedBox(height: 16),
          ],

          // KPIs
          Row(
            children: [
              Expanded(
                child: KPICard(
                  title: 'Total Units Suggested',
                  value: '$totalSuggested',
                  icon: Icons.shopping_bag,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Products Needing Action',
                  value: '$needingAction',
                  icon: Icons.warning_amber,
                  color: AppColors.warning,
                  isAlert: needingAction > 0,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: KPICard(
                  title: 'Est. Order Cost',
                  value: 'EGP ${estimatedCost.toStringAsFixed(0)}',
                  icon: Icons.attach_money,
                  color: cashFlow != null && estimatedCost > cashFlow.remainingBudget
                      ? AppColors.error
                      : AppColors.primary,
                  isAlert: cashFlow != null && estimatedCost > cashFlow.remainingBudget,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Search by SKU or Name',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _searchQuery = ''),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset'),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: _sortByPriority ? 'Sorted by priority (Critical first)' : 'Sort by priority',
                        child: FilterChip(
                          label: const Text('Priority'),
                          avatar: const Icon(Icons.sort, size: 14),
                          selected: _sortByPriority,
                          onSelected: (v) => setState(() => _sortByPriority = v),
                          selectedColor: AppColors.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _exportCsv(context, recommendations, productMap),
                        icon: const Icon(Icons.download),
                        label: const Text('Export'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  if (recommendations.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(
                          value: _selectAll,
                          onChanged: (v) {
                            setState(() {
                              _selectAll = v ?? false;
                              if (_selectAll) {
                                _selectedIds.addAll(recommendations.map((r) => r.productId));
                              } else {
                                _selectedIds.clear();
                              }
                            });
                          },
                        ),
                        Text(
                          'Select All (${_selectedIds.length}/${recommendations.length})',
                          style: AppTextStyles.body,
                        ),
                        const Spacer(),
                        if (_selectedIds.isNotEmpty)
                          ElevatedButton.icon(
                            onPressed: _bulkApproving
                                ? null
                                : () => _approveSelected(context, recommendations, productMap),
                            icon: _bulkApproving
                                ? const SizedBox(
                                    width: 16, height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.check_circle),
                            label: Text(_bulkApproving
                                ? 'Approving…'
                                : 'Approve ${_selectedIds.length} & Create Order'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  recommendations.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Column(
                            children: [
                              const Icon(Icons.check_circle, color: AppColors.success, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                'No replenishment needed — all stock levels are healthy.',
                                style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : HorizontallyScrollableTable(
                          child: DataTable(
                            columns: [
                              const DataColumn(label: SizedBox(width: 24)),
                              DataColumn(label: Text('PRODUCT', style: AppTextStyles.tableHeader)),
                              DataColumn(label: Text('TYPE', style: AppTextStyles.tableHeader)),
                              DataColumn(label: Text('STOCK', style: AppTextStyles.tableHeader), numeric: true),
                              DataColumn(label: Text('FORECAST', style: AppTextStyles.tableHeader), numeric: true),
                              DataColumn(label: Text('ROP', style: AppTextStyles.tableHeader), numeric: true),
                              DataColumn(label: Text('ORDER QTY', style: AppTextStyles.tableHeader), numeric: true),
                              DataColumn(label: Text('EST. ARRIVAL', style: AppTextStyles.tableHeader)),
                              DataColumn(label: Text('BUDGET', style: AppTextStyles.tableHeader)),
                              DataColumn(label: Text('STATUS', style: AppTextStyles.tableHeader)),
                              DataColumn(label: Text('ACTION', style: AppTextStyles.tableHeader)),
                            ],
                            rows: recommendations.map((r) {
                              final product = productMap[r.productId];
                              final isManufacture = product?.manufacturerId != null &&
                                  product!.manufacturerId!.isNotEmpty;
                              final isSelected = _selectedIds.contains(r.productId);
                              final adjustedVal = _adjustedQty[r.productId] ?? r.suggestedOrderQty;
                              final deviation = r.suggestedOrderQty > 0
                                  ? ((adjustedVal - r.suggestedOrderQty) / r.suggestedOrderQty * 100).round()
                                  : 0;
                              final rowCost = adjustedVal * (product?.unitCost ?? 0);
                              final overBudget = cashFlow != null && rowCost > cashFlow.remainingBudget;
                              return DataRow(
                                color: AppColors.dataRowColor,
                                selected: isSelected,
                                cells: [
                                  DataCell(
                                    Checkbox(
                                      value: isSelected,
                                      onChanged: (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selectedIds.add(r.productId);
                                          } else {
                                            _selectedIds.remove(r.productId);
                                          }
                                          _selectAll = _selectedIds.length == recommendations.length;
                                        });
                                      },
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      children: [
                                        Container(
                                          width: 32, height: 32,
                                          decoration: BoxDecoration(
                                            color: Colors.grey[200],
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Icon(
                                            isManufacture ? Icons.precision_manufacturing : Icons.inventory,
                                            size: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(r.productName,
                                                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                                            Text(r.sku, style: AppTextStyles.label),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Builder(builder: (context) {
                                      final manufacturers = {
                                        for (final m in context.watch<AppState>().manufacturers) m.id: m.name
                                      };
                                      final mfrId = product?.manufacturerId;
                                      final mfgName = isManufacture && mfrId != null && mfrId.isNotEmpty
                                          ? (manufacturers[mfrId] ?? 'Unknown')
                                          : null;
                                      final hasBom = context.watch<AppState>().boms
                                          .any((b) => b.finalProductId == r.productId);
                                      return Tooltip(
                                        message: isManufacture
                                            ? 'Manufacturer: ${mfgName ?? "not set"}\nBOM: ${hasBom ? "configured" : "MISSING — add one in BOM screen"}'
                                            : 'Sourced from supplier',
                                        child: Chip(
                                          avatar: isManufacture && !hasBom
                                              ? const Icon(Icons.warning_amber, size: 14, color: Colors.deepPurple)
                                              : null,
                                          label: Text(
                                            isManufacture ? 'Manufacture' : 'Purchase',
                                            style: TextStyle(
                                              color: isManufacture ? Colors.deepPurple : AppColors.primary,
                                              fontSize: 12,
                                            ),
                                          ),
                                          backgroundColor: isManufacture
                                              ? Colors.deepPurple.withValues(alpha: 0.1)
                                              : AppColors.primary.withValues(alpha: 0.1),
                                        ),
                                      );
                                    }),
                                  ),
                                  DataCell(Text('${r.currentStock}')),
                                  DataCell(Text('${r.forecastNextPeriod}')),
                                  DataCell(Text('${r.reorderPoint}')),
                                  DataCell(
                                    SizedBox(
                                      width: 90,
                                      child: TextFormField(
                                        initialValue: '$adjustedVal',
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                          suffixIcon: deviation.abs() > 30
                                              ? Tooltip(
                                                  message: '${deviation > 0 ? "+" : ""}$deviation% from suggestion',
                                                  child: const Icon(Icons.warning_amber, color: AppColors.warning, size: 16),
                                                )
                                              : null,
                                        ),
                                        style: AppTextStyles.body.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                        onChanged: (v) {
                                          final parsed = int.tryParse(v);
                                          if (parsed != null && parsed > 0) {
                                            setState(() => _adjustedQty[r.productId] = parsed);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  DataCell(_buildArrivalDate(r, product, supplierMap)),
                                  DataCell(
                                    cashFlow == null
                                        ? const Text('—', style: TextStyle(color: Colors.grey))
                                        : Tooltip(
                                            message: overBudget
                                                ? 'EGP ${rowCost.toStringAsFixed(0)} exceeds remaining budget'
                                                : 'Within budget',
                                            child: Icon(
                                              overBudget ? Icons.warning_amber : Icons.check_circle,
                                              color: overBudget ? AppColors.warning : AppColors.success,
                                              size: 18,
                                            ),
                                          ),
                                  ),
                                  DataCell(StatusChip(r.status)),
                                  DataCell(_buildApproveButton(context, r, product)),
                                ],
                              );
                            }).toList(),
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

// ── Budget Card ──────────────────────────────────────────────────────────────

class _BudgetCard extends StatelessWidget {
  final double remainingBudget;
  final double estimatedCost;

  const _BudgetCard({required this.remainingBudget, required this.estimatedCost});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'en');
    final overBudget = estimatedCost > remainingBudget;
    final pct = remainingBudget > 0 ? (estimatedCost / remainingBudget).clamp(0.0, 1.0) : 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet, color: overBudget ? AppColors.error : AppColors.primary),
                const SizedBox(width: 8),
                Text('Budget Constraint', style: AppTextStyles.h3),
                const Spacer(),
                if (overBudget)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Over Budget',
                      style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Within Budget',
                      style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Available Budget', style: AppTextStyles.label),
                      Text('EGP ${fmt.format(remainingBudget)}',
                          style: AppTextStyles.h2.copyWith(color: AppColors.success)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Est. Order Cost', style: AppTextStyles.label),
                      Text(
                        'EGP ${fmt.format(estimatedCost)}',
                        style: AppTextStyles.h2.copyWith(
                          color: overBudget ? AppColors.error : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Remaining After Orders', style: AppTextStyles.label),
                      Text(
                        'EGP ${fmt.format(remainingBudget - estimatedCost)}',
                        style: AppTextStyles.h2.copyWith(
                          color: overBudget ? AppColors.error : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: AppColors.border,
                color: overBudget ? AppColors.error : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── BOM Confirmation Dialog ──────────────────────────────────────────────────

class _BomConfirmDialog extends StatelessWidget {
  final ReplenishmentRecommendation rec;
  final int adjustedQty;
  final AppState state;

  const _BomConfirmDialog({
    required this.rec,
    required this.adjustedQty,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final bom = state.boms.where((b) => b.finalProductId == rec.productId).firstOrNull;
    final rmMap = {for (final m in state.rawMaterials) m.id: m};
    final mfrMap = {for (final m in state.manufacturers) m.id: m};
    final product = state.products.where((p) => p.id == rec.productId).firstOrNull;
    final manufacturer = product?.manufacturerId != null ? mfrMap[product!.manufacturerId] : null;
    final fmt = NumberFormat('#,##0.##', 'en');

    final hasBom = bom != null;
    double totalRmCost = 0;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.precision_manufacturing, color: Colors.deepPurple),
          const SizedBox(width: 8),
          Expanded(child: Text('Confirm Production Order', style: AppTextStyles.h3)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Product + quantity summary
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2, color: Colors.deepPurple, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rec.productName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                          Text('SKU: ${rec.sku}  •  Quantity: $adjustedQty units', style: AppTextStyles.label),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Manufacturer
              Row(
                children: [
                  const Icon(Icons.factory, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text('Manufacturer: ', style: AppTextStyles.label),
                  Text(
                    manufacturer?.name ?? 'NOT SET — assign one in Products',
                    style: AppTextStyles.body.copyWith(
                      color: manufacturer == null ? AppColors.error : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // BOM breakdown
              Text('Raw Materials Required (from BOM)', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              if (!hasBom)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No BOM found for this product. Add one in the BOM screen before creating a production order.',
                          style: AppTextStyles.body.copyWith(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...bom.materials.map((mat) {
                  final rm = rmMap[mat.rawMaterialId];
                  final totalQty = mat.quantityPerUnit * adjustedQty;
                  final lineCost = totalQty * (rm?.unitCost ?? 0);
                  totalRmCost += lineCost;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 6, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            rm?.name ?? mat.rawMaterialId,
                            style: AppTextStyles.body,
                          ),
                        ),
                        Text(
                          '${fmt.format(totalQty)} ${rm?.unit ?? 'units'}',
                          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'EGP ${fmt.format(lineCost)}',
                          style: AppTextStyles.label,
                        ),
                      ],
                    ),
                  );
                }),

              if (hasBom) ...[
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('Total Raw Material Cost: ', style: AppTextStyles.label),
                    Text(
                      'EGP ${fmt.format(totalRmCost)}',
                      style: AppTextStyles.h3.copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ],

              if (manufacturer != null && manufacturer.contactEmail.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.email, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Manufacturer email will be sent to ${manufacturer.contactEmail}',
                      style: AppTextStyles.label,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: hasBom && manufacturer != null
              ? () => Navigator.pop(context, true)
              : null,
          icon: const Icon(Icons.check),
          label: const Text('Create Production Order'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ── Urgent Stock Context Card ─────────────────────────────────────────────────

class _UrgentStockContextCard extends StatelessWidget {
  final String productId;
  final AppState state;

  const _UrgentStockContextCard({required this.productId, required this.state});

  @override
  Widget build(BuildContext context) {
    final result =
        state.minimumStockResults.where((r) => r.productId == productId).firstOrNull;
    if (result == null || !result.isUrgent) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${result.productName} is critically low',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.error)),
                const SizedBox(height: 2),
                Text(
                  'Current stock: ${result.currentStock} units  |  '
                  'Min stock: ${result.minimumStock} units  |  '
                  'Stockout in ~${result.daysOfStockLeft.toStringAsFixed(0)} days',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.error),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Lead Time Summary Card ────────────────────────────────────────────────────

class _LeadTimeSummaryCard extends StatelessWidget {
  final String productId;
  final AppState state;

  const _LeadTimeSummaryCard({required this.productId, required this.state});

  @override
  Widget build(BuildContext context) {
    final result = state.minimumStockResults
        .where((r) => r.productId == productId)
        .firstOrNull;

    final product =
        state.products.where((p) => p.id == productId).firstOrNull;

    final totalDays =
        result?.totalLeadTimeDays ?? product?.leadTimeDays ?? 0;
    final rmDays = result?.rmLeadTimeDays ?? 0;
    final mfgDays = result?.manufacturingDays ?? product?.leadTimeDays ?? 0;

    if (totalDays == 0) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.timer_outlined,
                color: AppColors.warning, size: 16),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Set lead time for accurate ROP — edit product or raw material lead times.',
                style:
                    TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    // Find the bottleneck RM supplier
    final bom = state.boms
        .where((b) => b.finalProductId == productId && b.isActive)
        .firstOrNull;
    String? bottleneckLabel;
    if (bom != null && rmDays > 0) {
      for (final line in bom.materials) {
        final rm = state.rawMaterials
            .where((r) => r.id == line.rawMaterialId)
            .firstOrNull;
        if (rm != null && rm.leadTimeDays == rmDays) {
          final supplier = rm.supplierId != null
              ? state.suppliers
                  .where((s) => s.id == rm.supplierId)
                  .firstOrNull
              : null;
          bottleneckLabel =
              '${rm.name}${supplier != null ? ' from ${supplier.name}' : ''}';
          break;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Total Lead Time: $totalDays days',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.textPrimary)),
            ],
          ),
          if (rmDays > 0) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                'Raw Material Procurement: $rmDays days'
                '${bottleneckLabel != null ? ' ($bottleneckLabel)' : ''}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
          if (mfgDays > 0) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                'Manufacturing: $mfgDays days',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Raw Material Order CTA ────────────────────────────────────────────────────

class _RmOrderCta extends StatelessWidget {
  final String productId;
  final double forecastQty;
  final AppState state;

  const _RmOrderCta({
    required this.productId,
    required this.forecastQty,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final product =
        state.products.where((p) => p.id == productId).firstOrNull;
    final bom = state.boms
        .where((b) => b.finalProductId == productId && b.isActive)
        .firstOrNull;

    if (bom == null || forecastQty <= 0) return const SizedBox.shrink();

    // Build preview lines grouped by supplier
    final bySupplier = <String, List<Map<String, dynamic>>>{};
    for (final line in bom.materials) {
      final rm = state.rawMaterials
          .where((r) => r.id == line.rawMaterialId)
          .firstOrNull;
      if (rm == null) continue;
      final sid = rm.supplierId ?? '_unassigned';
      final supplier = rm.supplierId != null
          ? state.suppliers
              .where((s) => s.id == rm.supplierId)
              .firstOrNull
          : null;
      final totalQty = line.quantityPerUnit * forecastQty;
      bySupplier.putIfAbsent(sid, () => []).add({
        'rmName': rm.name,
        'qty': totalQty,
        'uom': line.unitOfMeasure.isNotEmpty ? line.unitOfMeasure : rm.unitOfMeasure,
        'qtyPerUnit': line.quantityPerUnit,
        'supplierName': supplier?.name ?? 'Unassigned',
      });
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Order Raw Materials for this Forecast',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Based on your forecast (next period: ${forecastQty.toStringAsFixed(0)} units) '
              'and BOM for ${product?.name ?? "this product"}, you need:',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ...bySupplier.entries.map((entry) {
              final lines = entry.value;
              final supplierName = lines.first['supplierName'] as String;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('From $supplierName:',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    ...lines.map((l) => Padding(
                          padding: const EdgeInsets.only(left: 12, top: 2),
                          child: Text(
                            '• ${l['rmName']}  →  ${(l['qty'] as double).toStringAsFixed(1)} ${l['uom']} '
                            '(${(l['qtyPerUnit'] as double).toStringAsFixed(1)} × ${forecastQty.toStringAsFixed(0)})',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary),
                          ),
                        )),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => context.go(
                  '/orders/raw-materials/create'
                  '?productId=$productId'
                  '&qty=${forecastQty.toStringAsFixed(0)}',
                ),
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('Review & Create Orders'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
