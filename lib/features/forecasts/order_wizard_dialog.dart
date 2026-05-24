/// Unified "forecast → order" wizard.
///
/// Replaces the old two-step flow of (a) viewing a forecast then (b) jumping
/// to the Replenishment screen to approve a recommendation. The wizard
/// automatically branches on whether the product is **supplied** (has a
/// `supplierId`) or **manufactured in-house** (has a `manufacturerId`), and
/// reuses the existing `AppState` approval methods so all downstream side
/// effects (PurchaseOrder, SupplierOrder, ProductionOrder, raw-material
/// orders, supplier / manufacturer / factory emails) stay in one place.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:ma5zony/models/forecast_result.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/raw_material.dart';
import 'package:ma5zony/models/replenishment_recommendation.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';

/// Entry point. Opens the wizard as a modal dialog.
Future<void> showOrderWizardDialog({
  required BuildContext context,
  required Product product,
  required ForecastResult forecast,
  required int leadTimeDays,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _OrderWizardDialog(
      product: product,
      forecast: forecast,
      leadTimeDays: leadTimeDays,
    ),
  );
}

/// Tells us which branch the wizard is on.
enum _Branch { supplier, manufactured, unconfigured }

class _OrderWizardDialog extends StatefulWidget {
  final Product product;
  final ForecastResult forecast;
  final int leadTimeDays;

  const _OrderWizardDialog({
    required this.product,
    required this.forecast,
    required this.leadTimeDays,
  });

  @override
  State<_OrderWizardDialog> createState() => _OrderWizardDialogState();
}

class _OrderWizardDialogState extends State<_OrderWizardDialog> {
  late final TextEditingController _qtyCtrl;
  late int _qty;
  bool _busy = false;
  String? _error;
  _ResultBanner? _result;

  @override
  void initState() {
    super.initState();
    _qty = _initialSuggestedQty();
    _qtyCtrl = TextEditingController(text: _qty.toString());
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  int _initialSuggestedQty() {
    // Scale the next-period (monthly) forecast by the lead time so we cover
    // demand during reorder, with a floor of 1 if a forecast exists.
    final next = widget.forecast.nextPeriodForecast;
    final lt = widget.leadTimeDays;
    final scaled = lt > 0 ? next * (lt / 30.0) : next;
    final ceil = scaled.ceil();
    return ceil <= 0 ? 0 : ceil;
  }

  _Branch _detectBranch() {
    final hasMfr = (widget.product.manufacturerId ?? '').isNotEmpty;
    final hasSupplier = (widget.product.supplierId ?? '').isNotEmpty;
    if (hasMfr) return _Branch.manufactured;
    if (hasSupplier) return _Branch.supplier;
    return _Branch.unconfigured;
  }

  ReplenishmentRecommendation _buildRecommendation() {
    return ReplenishmentRecommendation(
      productId: widget.product.id,
      productName: widget.product.name,
      sku: widget.product.sku,
      currentStock: 0, // not used by the approval methods
      forecastNextPeriod: widget.forecast.nextPeriodForecast.round(),
      reorderPoint: 0,
      suggestedOrderQty: _qty,
      recommendedOrderDate: DateTime.now(),
      urgency: 'Normal',
    );
  }

  Future<void> _runAction(Future<void> Function() body, String successMsg) async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      await body();
      if (!mounted) return;
      setState(() => _result = _ResultBanner.success(successMsg));
    } on BomMissingException {
      setState(() => _error =
          'No active Bill of Materials found for this product. '
          'Add one in the BOM screen, then re-open this wizard.');
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final state = context.read<AppState>();
    final branch = _detectBranch();
    final rec = _buildRecommendation();
    if (branch == _Branch.manufactured) {
      await _runAction(
        () => state.approveReplenishmentManufacture(rec),
        'Production order created and emails sent to factory + manufacturer.',
      );
    } else {
      await _runAction(
        () => state.approveRecommendation(rec),
        'Purchase order confirmed and email sent to supplier.',
      );
    }
  }

  Future<void> _saveDraft() async {
    final state = context.read<AppState>();
    final branch = _detectBranch();
    final rec = _buildRecommendation();
    if (branch == _Branch.manufactured) {
      await _runAction(
        () async {
          await state.saveDraftProductionOrderFromRecommendation(rec);
        },
        'Production order saved as draft. Approve later from Replenishment.',
      );
    } else {
      await _runAction(
        () async {
          await state.saveDraftPOFromRecommendation(rec);
        },
        'Purchase order saved as draft. Approve later from Replenishment.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final branch = _detectBranch();
    final media = MediaQuery.of(context);
    final maxWidth = media.size.width < 720 ? media.size.width - 32 : 680.0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: media.size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(branch),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_result != null) ...[
                      _result!,
                      const SizedBox(height: 16),
                    ],
                    _BranchSummaryCard(
                      branch: branch,
                      product: widget.product,
                      state: state,
                    ),
                    const SizedBox(height: 16),
                    _OrderDetailsSection(
                      qtyCtrl: _qtyCtrl,
                      onQtyChanged: (v) => setState(() => _qty = v),
                      unitCost: widget.product.unitCost,
                      leadTimeDays: widget.leadTimeDays,
                      forecastNextPeriod:
                          widget.forecast.nextPeriodForecast,
                    ),
                    const SizedBox(height: 16),
                    if (branch == _Branch.manufactured)
                      _BomBreakdownSection(
                        product: widget.product,
                        state: state,
                        orderQty: _qty,
                      )
                    else if (branch == _Branch.supplier)
                      _SupplierContactSection(
                        product: widget.product,
                        state: state,
                      )
                    else
                      _UnconfiguredCard(productId: widget.product.id),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _ResultBanner.error(_error!),
                    ],
                  ],
                ),
              ),
            ),
            _buildFooter(branch),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(_Branch branch) {
    final isMfr = branch == _Branch.manufactured;
    final color = isMfr ? AppColors.primary : AppColors.success;
    final label = switch (branch) {
      _Branch.manufactured => 'Manufacturing Order',
      _Branch.supplier => 'Supplier Purchase Order',
      _Branch.unconfigured => 'Order',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(isMfr ? Icons.precision_manufacturing : Icons.local_shipping,
              color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: color)),
                const SizedBox(height: 2),
                Text(widget.product.name,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          IconButton(
            onPressed:
                _busy ? null : () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(_Branch branch) {
    final canSubmit = !_busy &&
        _qty > 0 &&
        branch != _Branch.unconfigured &&
        _result == null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (_busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (_busy) const SizedBox(width: 12),
          if (_result != null)
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check),
                label: const Text('Done'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success),
              ),
            )
          else ...[
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
              child: const Text('Cancel'),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: canSubmit ? _saveDraft : null,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save as Draft'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: canSubmit ? _approve : null,
              icon: Icon(
                  branch == _Branch.manufactured
                      ? Icons.precision_manufacturing
                      : Icons.send_outlined,
                  size: 18),
              label: Text(branch == _Branch.manufactured
                  ? 'Approve & Notify Factory'
                  : 'Approve & Email Supplier'),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subviews
// ─────────────────────────────────────────────────────────────────────────────

class _BranchSummaryCard extends StatelessWidget {
  final _Branch branch;
  final Product product;
  final AppState state;
  const _BranchSummaryCard({
    required this.branch,
    required this.product,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (branch) {
      _Branch.supplier =>
        'This product is purchased from a supplier. We will create a '
            'Purchase Order and email the supplier on approval.',
      _Branch.manufactured =>
        'This product is manufactured in-house. We will create a '
            'Production Order and trigger raw-material orders + emails on '
            'approval.',
      _Branch.unconfigured =>
        'This product has neither a supplier nor a manufacturer assigned. '
            'Open the Products screen and assign one before ordering.',
    };
    final icon = switch (branch) {
      _Branch.supplier => Icons.storefront_outlined,
      _Branch.manufactured => Icons.factory_outlined,
      _Branch.unconfigured => Icons.warning_amber_rounded,
    };
    final color = switch (branch) {
      _Branch.supplier => AppColors.primary,
      _Branch.manufactured => AppColors.primary,
      _Branch.unconfigured => AppColors.warning,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _OrderDetailsSection extends StatelessWidget {
  final TextEditingController qtyCtrl;
  final ValueChanged<int> onQtyChanged;
  final double unitCost;
  final int leadTimeDays;
  final double forecastNextPeriod;

  const _OrderDetailsSection({
    required this.qtyCtrl,
    required this.onQtyChanged,
    required this.unitCost,
    required this.leadTimeDays,
    required this.forecastNextPeriod,
  });

  @override
  Widget build(BuildContext context) {
    final qty = int.tryParse(qtyCtrl.text) ?? 0;
    final total = qty * unitCost;
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
          const Text('Order details',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Order quantity (units)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v) ?? 0;
                    onQtyChanged(parsed < 0 ? 0 : parsed);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ReadOnlyField(
                    label: 'Lead time',
                    value: '$leadTimeDays day(s)'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ReadOnlyField(
                    label: 'Unit cost',
                    value: 'EGP ${unitCost.toStringAsFixed(2)}'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ReadOnlyField(
                    label: 'Estimated total',
                    value: 'EGP ${total.toStringAsFixed(2)}',
                    highlight: true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Forecast next 30 days: ${forecastNextPeriod.toStringAsFixed(1)} units. '
            'Default quantity is sized to cover the lead-time window.',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _ReadOnlyField({
    required this.label,
    required this.value,
    this.highlight = false,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.06)
            : AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: highlight
                      ? AppColors.primary
                      : AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _SupplierContactSection extends StatelessWidget {
  final Product product;
  final AppState state;
  const _SupplierContactSection({required this.product, required this.state});

  @override
  Widget build(BuildContext context) {
    final supplier = state.suppliers
        .where((s) => s.id == product.supplierId)
        .firstOrNull;
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
          const Text('Supplier',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 10),
          if (supplier == null)
            const Text('Supplier not found.',
                style: TextStyle(color: AppColors.error, fontSize: 12))
          else ...[
            _kv('Name', supplier.name),
            _kv('Email',
                supplier.contactEmail.isEmpty ? '—' : supplier.contactEmail),
            _kv('Lead time', '${supplier.typicalLeadTimeDays} day(s)'),
            if (supplier.contactEmail.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'No email on file — the PO will be saved but no email '
                    'will be sent. Add an email to the supplier first.',
                    style: TextStyle(
                        color: AppColors.warning, fontSize: 12),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 90,
                child: Text(k,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500))),
          ],
        ),
      );
}

class _BomBreakdownSection extends StatelessWidget {
  final Product product;
  final AppState state;
  final int orderQty;

  const _BomBreakdownSection({
    required this.product,
    required this.state,
    required this.orderQty,
  });

  @override
  Widget build(BuildContext context) {
    final bom = state.boms
        .where((b) => b.finalProductId == product.id && b.isActive)
        .firstOrNull;
    final manufacturer = state.manufacturers
        .where((m) => m.id == product.manufacturerId)
        .firstOrNull;

    if (bom == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Icon(Icons.warning_amber_rounded,
                  color: AppColors.warning, size: 20),
              SizedBox(width: 8),
              Text('Bill of Materials missing',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.warning)),
            ]),
            const SizedBox(height: 8),
            const Text(
              'Approval is disabled until a BOM exists for this product. '
              'Define the raw materials and quantities needed per unit, '
              'then return here to send the order.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go('/bom');
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Open BOM editor'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.warning),
              ),
            ),
          ],
        ),
      );
    }

    final rows = <_BomRow>[];
    double rmCostTotal = 0;
    for (final mat in bom.materials) {
      final rm = state.rawMaterials
          .where((r) => r.id == mat.rawMaterialId)
          .firstOrNull;
      final required = mat.quantityPerUnit * orderQty;
      final unitCost = rm?.unitCost ?? 0;
      final lineCost = required * unitCost;
      rmCostTotal += lineCost;
      rows.add(_BomRow(
        name: rm?.name ?? mat.rawMaterialId,
        unit: mat.unitOfMeasure,
        perUnit: mat.quantityPerUnit,
        required: required,
        onHand: (rm?.currentStock ?? 0).toDouble(),
        lineCost: lineCost,
        rm: rm,
      ));
    }

    final productionFee = (product.productionFee ?? 0) * orderQty;
    final grandTotal = rmCostTotal + productionFee;

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
          const Text('Raw materials required',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            'Computed for an order of $orderQty unit(s). Shortfalls trigger '
            'automatic raw-material orders on approval.',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          ..._buildBomTable(rows),
          const Divider(height: 24),
          if (manufacturer != null) ...[
            _kv('Manufacturer', manufacturer.name),
            _kv('Email',
                manufacturer.contactEmail.isEmpty
                    ? '—'
                    : manufacturer.contactEmail),
            _kv('Production lead',
                '${manufacturer.typicalProductionDays} day(s)'),
            const SizedBox(height: 8),
          ],
          _kv('Raw material cost',
              'EGP ${rmCostTotal.toStringAsFixed(2)}'),
          if (productionFee > 0)
            _kv('Production fee',
                'EGP ${productionFee.toStringAsFixed(2)}'),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Estimated production cost',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                Text('EGP ${grandTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBomTable(List<_BomRow> rows) {
    final widgets = <Widget>[
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(flex: 4, child: Text('Material', style: _hdrStyle)),
            Expanded(flex: 2, child: Text('Need', style: _hdrStyle)),
            Expanded(flex: 2, child: Text('On hand', style: _hdrStyle)),
            Expanded(flex: 2, child: Text('Line cost', style: _hdrStyle)),
          ],
        ),
      ),
      const Divider(height: 1),
    ];
    for (final r in rows) {
      final short = r.required > r.onHand;
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
                flex: 4,
                child: Text(r.name,
                    style: const TextStyle(fontSize: 12))),
            Expanded(
                flex: 2,
                child: Text(
                  '${_fmt(r.required)} ${r.unit}',
                  style: TextStyle(
                      fontSize: 12,
                      color: short ? AppColors.error : AppColors.textPrimary,
                      fontWeight: short ? FontWeight.w700 : FontWeight.w500),
                )),
            Expanded(
                flex: 2,
                child: Text(_fmt(r.onHand),
                    style: const TextStyle(fontSize: 12))),
            Expanded(
                flex: 2,
                child: Text(
                  'EGP ${r.lineCost.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12),
                )),
          ],
        ),
      ));
    }
    return widgets;
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
                width: 130,
                child: Text(k,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500))),
          ],
        ),
      );

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

const _hdrStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary);

class _BomRow {
  final String name;
  final String unit;
  final double perUnit;
  final double required;
  final double onHand;
  final double lineCost;
  final RawMaterial? rm;
  _BomRow({
    required this.name,
    required this.unit,
    required this.perUnit,
    required this.required,
    required this.onHand,
    required this.lineCost,
    required this.rm,
  });
}

class _UnconfiguredCard extends StatelessWidget {
  final String productId;
  const _UnconfiguredCard({required this.productId});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 20),
            SizedBox(width: 8),
            Text('No supplier or manufacturer assigned',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning)),
          ]),
          const SizedBox(height: 8),
          const Text(
            'Assign a supplier (for purchased products) or a manufacturer '
            '(for in-house production) before placing an order.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.go('/products');
              },
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Edit product'),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status banner
// ─────────────────────────────────────────────────────────────────────────────

class _ResultBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color color;
  const _ResultBanner({
    required this.message,
    required this.icon,
    required this.color,
  });

  factory _ResultBanner.success(String msg) => _ResultBanner(
        message: msg,
        icon: Icons.check_circle,
        color: AppColors.success,
      );

  factory _ResultBanner.error(String msg) => _ResultBanner(
        message: msg,
        icon: Icons.error_outline,
        color: AppColors.error,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

