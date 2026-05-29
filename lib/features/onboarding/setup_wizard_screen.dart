import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/models/manufacturer.dart';
import 'package:ma5zony/models/raw_material.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/models/warehouse.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';
import 'package:ma5zony/widgets/shared_widgets.dart';

class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  int _currentStep = 0;
  bool _loading = false;

  // Step 1: Shopify
  final _domainCtrl = TextEditingController();
  bool _shopifyConnecting = false;
  bool _shopifyConnected = false;

  // Step 2: Sync
  Map<String, int>? _productSyncResult;
  Map<String, dynamic>? _orderSyncResult;
  bool _syncing = false;

  // Step 3: Raw Materials
  final List<_RmRow> _rmRows = [];

  // Step 4: BOM setup
  String? _selectedProductId;
  final List<_BomRow> _bomRows = [];

  // Step 5: Warehouse
  final _warehouseNameCtrl = TextEditingController();
  final _warehouseAddressCtrl = TextEditingController();
  final _warehouseCityCtrl = TextEditingController();
  bool _warehouseSaved = false;
  String? _savedWarehouseId;
  List<String> _assignedProductIds = [];

  // Step 6: Locations
  final Map<String, TextEditingController> _supplierAddressCtrls = {};
  final Map<String, TextEditingController> _mfrAddressCtrls = {};

  @override
  void dispose() {
    _domainCtrl.dispose();
    _warehouseNameCtrl.dispose();
    _warehouseAddressCtrl.dispose();
    _warehouseCityCtrl.dispose();
    for (final row in _rmRows) {
      row.dispose();
    }
    for (final row in _bomRows) {
      row.dispose();
    }
    for (final c in _supplierAddressCtrls.values) {
      c.dispose();
    }
    for (final c in _mfrAddressCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<AppState>();
    // Populate address controllers for existing suppliers/manufacturers
    for (final s in state.suppliers) {
      _supplierAddressCtrls.putIfAbsent(
        s.id, () => TextEditingController(text: s.address ?? ''));
    }
    for (final m in state.manufacturers) {
      _mfrAddressCtrls.putIfAbsent(
        m.id, () => TextEditingController(text: m.address ?? ''));
    }
  }

  void _next() => setState(() {
        if (_currentStep < 5) _currentStep++;
      });

  void _back() => setState(() {
        if (_currentStep > 0) _currentStep--;
      });

  Future<void> _finish() async {
    final state = context.read<AppState>();
    await state.completeOnboardingStep('done');
    if (mounted) context.go('/dashboard');
  }

  // ── Step 1: Shopify ──────────────────────────────────────────────────────

  Future<void> _connectShopify() async {
    final state = context.read<AppState>();
    final domain = _domainCtrl.text.trim();
    if (domain.isEmpty) return;
    setState(() => _shopifyConnecting = true);
    try {
      final url = await state.getShopifyOAuthUrl(domain);
      if (url != null && await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        await state.connectShopify(domain);
        setState(() => _shopifyConnected = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 3), content: Text('Connection failed: $e'),
              backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _shopifyConnecting = false);
    }
  }

  // ── Step 2: Sync ─────────────────────────────────────────────────────────

  Future<void> _syncProducts() async {
    // Open the product picker dialog — user selects exactly which products
    // to import rather than pulling everything from Shopify automatically.
    final result = await ShopifyProductPickerDialog.show(context);
    if (result != null && mounted) {
      setState(() => _productSyncResult = result);
    }
  }

  Future<void> _syncOrders() async {
    setState(() => _syncing = true);
    try {
      final result = await context.read<AppState>().importShopifyOrders();
      setState(() => _orderSyncResult = result);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // ── Step 3: Save raw materials ────────────────────────────────────────────

  Future<void> _saveRawMaterials() async {
    final state = context.read<AppState>();
    setState(() => _loading = true);
    try {
      for (final row in _rmRows) {
        if (row.name.text.trim().isEmpty) continue;
        final rm = RawMaterial(
          id: '',
          name: row.name.text.trim(),
          sku: row.sku.text.trim(),
          unit: row.unit,
          unitOfMeasure: row.unit,
          unitCost: double.tryParse(row.unitCost.text) ?? 0,
          supplierId: row.selectedSupplierId,
          leadTimeDays: int.tryParse(row.leadTime.text) ?? 0,
        );
        await state.addRawMaterial(rm);
      }
      _next();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Step 4: Save BOM ─────────────────────────────────────────────────────

  Future<void> _saveBOM() async {
    if (_selectedProductId == null || _bomRows.isEmpty) {
      _next();
      return;
    }
    final state = context.read<AppState>();
    setState(() => _loading = true);
    try {
      final materials = _bomRows
          .where((r) => r.selectedRmId != null)
          .map((r) => BomMaterial(
                rawMaterialId: r.selectedRmId!,
                quantityPerUnit: double.tryParse(r.qty.text) ?? 1,
                unitOfMeasure: r.uom,
              ))
          .toList();
      if (materials.isNotEmpty) {
        await state.addBOM(BillOfMaterials(
          id: '',
          finalProductId: _selectedProductId!,
          materials: materials,
          isActive: true,
        ));
      }
      _next();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Step 5: Save warehouse + assign products ──────────────────────────────

  Future<void> _saveWarehouse() async {
    final name = _warehouseNameCtrl.text.trim();
    if (name.isEmpty) return;
    final state = context.read<AppState>();
    setState(() => _loading = true);
    try {
      final saved = await state.addWarehouseAndReturn(Warehouse(
        id: '',
        name: name,
        city: _warehouseCityCtrl.text.trim(),
        country: '',
        address: _warehouseAddressCtrl.text.trim(),
      ));
      _savedWarehouseId = saved?.id;
      setState(() => _warehouseSaved = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assignProducts() async {
    if (_savedWarehouseId == null || _assignedProductIds.isEmpty) return;
    final state = context.read<AppState>();
    setState(() => _loading = true);
    try {
      await state.assignProductsToWarehouse(_savedWarehouseId, _assignedProductIds);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Step 6: Save locations ────────────────────────────────────────────────

  Future<void> _saveLocations() async {
    final state = context.read<AppState>();
    setState(() => _loading = true);
    try {
      for (final s in state.suppliers) {
        final addr = _supplierAddressCtrls[s.id]?.text.trim();
        if (addr != null && addr != s.address) {
          await state.updateSupplier(Supplier(
            id: s.id,
            name: s.name,
            contactEmail: s.contactEmail,
            phone: s.phone,
            typicalLeadTimeDays: s.typicalLeadTimeDays,
            performanceRating: s.performanceRating,
            address: addr.isEmpty ? null : addr,
            latitude: s.latitude,
            longitude: s.longitude,
            suppliedRawMaterialIds: s.suppliedRawMaterialIds,
          ));
        }
      }
      for (final m in state.manufacturers) {
        final addr = _mfrAddressCtrls[m.id]?.text.trim();
        if (addr != null && addr != m.address) {
          await state.updateManufacturer(Manufacturer(
            id: m.id,
            name: m.name,
            contactEmail: m.contactEmail,
            phone: m.phone,
            productionCapacity: m.productionCapacity,
            typicalProductionDays: m.typicalProductionDays,
            address: addr.isEmpty ? null : addr,
          ));
        }
      }
      await _finish();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      'Connect Shopify',
      'Import Products & Sales History',
      'Optional · Add Raw Materials',
      'Optional · Link Materials to Products (BOM)',
      'Optional · Set Up Warehouse',
      'Optional · Add Locations',
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(steps),
            Expanded(child: _buildStepContent()),
            _buildNavRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(List<String> steps) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/logo.png', height: 32,
                  errorBuilder: (_, _, _) => const SizedBox()),
              const SizedBox(width: 12),
              Text('Ma5zony Setup',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const Spacer(),
              TextButton.icon(
                onPressed: _finish,
                icon: Icon(Icons.skip_next, size: 16,
                    color: AppColors.textSecondary),
                label: Text(
                  _currentStep >= 2 ? 'Finish later' : 'Skip setup',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _StepProgressBar(currentStep: _currentStep, totalSteps: steps.length),
          const SizedBox(height: 8),
          Text(
            'Step ${_currentStep + 1} of ${steps.length}: ${steps[_currentStep]}',
            style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_currentStep >= 2) _ReadyToGoBanner(onFinish: _finish),
              switch (_currentStep) {
            0 => _Step1Shopify(
                domainCtrl: _domainCtrl,
                connecting: _shopifyConnecting,
                connected: _shopifyConnected,
                onConnect: _connectShopify,
              ),
            1 => _Step2Sync(
                syncing: false,
                productResult: _productSyncResult,
                orderResult: _orderSyncResult,
                onSyncProducts: _syncProducts,
                onSyncOrders: _syncOrders,
              ),
            2 => _Step3RawMaterials(
                rows: _rmRows,
                onAddRow: () => setState(() => _rmRows.add(_RmRow())),
                onRemoveRow: (i) => setState(() {
                  _rmRows[i].dispose();
                  _rmRows.removeAt(i);
                }),
              ),
            3 => _Step4BOM(
                selectedProductId: _selectedProductId,
                onProductChanged: (id) =>
                    setState(() => _selectedProductId = id),
                bomRows: _bomRows,
                onAddBomRow: () => setState(() => _bomRows.add(_BomRow())),
                onRemoveBomRow: (i) => setState(() {
                  _bomRows[i].dispose();
                  _bomRows.removeAt(i);
                }),
              ),
            4 => _Step5Warehouse(
                nameCtrl: _warehouseNameCtrl,
                addressCtrl: _warehouseAddressCtrl,
                cityCtrl: _warehouseCityCtrl,
                saved: _warehouseSaved,
                onSave: _saveWarehouse,
                onAssign: _assignProducts,
                assignedProductIds: _assignedProductIds,
                onAssignedChanged: (ids) =>
                    setState(() => _assignedProductIds = ids),
              ),
            5 => _Step6Locations(
                supplierAddressCtrls: _supplierAddressCtrls,
                mfrAddressCtrls: _mfrAddressCtrls,
              ),
            _ => const SizedBox(),
          },
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavRow() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Row(
        children: [
          if (_currentStep > 0)
            OutlinedButton(
              onPressed: _loading ? null : _back,
              child: const Text('Back'),
            ),
          const Spacer(),
          if (_currentStep >= 1) ...[
            TextButton.icon(
              onPressed: _loading ? null : _finish,
              icon: const Icon(Icons.dashboard_outlined, size: 18),
              label: const Text("I'm done — Go to dashboard"),
            ),
            const SizedBox(width: 12),
          ],
          if (_currentStep < 5)
            FilledButton(
              onPressed: _loading ? null : _handleNext,
              child: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: Colors.white))
                  : const Text('Continue'),
            )
          else
            FilledButton(
              onPressed: _loading ? null : _saveLocations,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
              child: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: Colors.white))
                  : const Text('Finish Setup'),
            ),
        ],
      ),
    );
  }

  void _handleNext() {
    switch (_currentStep) {
      case 0:
        _next(); // Shopify is optional
      case 1:
        _next(); // Sync is optional
      case 2:
        _rmRows.isEmpty ? _next() : _saveRawMaterials();
      case 3:
        _saveBOM();
      case 4:
        if (_warehouseSaved) {
          _assignProducts().then((_) => _next());
        } else {
          _next();
        }
      default:
        _next();
    }
  }
}

// ── Step Widgets ─────────────────────────────────────────────────────────────

class _Step1Shopify extends StatelessWidget {
  final TextEditingController domainCtrl;
  final bool connecting;
  final bool connected;
  final VoidCallback onConnect;

  const _Step1Shopify({
    required this.domainCtrl,
    required this.connecting,
    required this.connected,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final alreadyConnected = state.shopifyConnection?.isConnected ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WizardCard(
          title: 'Connect Your Shopify Store',
          subtitle: 'Enter your Shopify store domain to pull SKUs, inventory, '
              'and order history.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (alreadyConnected || connected)
                _SuccessBadge('Connected to ${state.shopifyConnection?.shopDomain ?? "Shopify"}')
              else ...[
                TextField(
                  controller: domainCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Store domain',
                    hintText: 'mystore.myshopify.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: connecting ? null : onConnect,
                  child: connecting
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Connect Shopify'),
                ),
              ],
              const SizedBox(height: 8),
              Text('You can also do this later in Integrations.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Step2Sync extends StatelessWidget {
  final bool syncing;
  final Map<String, int>? productResult;
  final Map<String, dynamic>? orderResult;
  final VoidCallback onSyncProducts;
  final VoidCallback onSyncOrders;

  const _Step2Sync({
    required this.syncing,
    required this.productResult,
    required this.orderResult,
    required this.onSyncProducts,
    required this.onSyncOrders,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WizardCard(
          title: 'Sync Your Shopify Data',
          subtitle: 'Import your product catalog and order history as demand data.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FilledButton(
                    onPressed: syncing ? null : onSyncProducts,
                    child: const Text('Sync Products (SKUs)'),
                  ),
                  const SizedBox(width: 12),
                  if (productResult != null)
                    _SuccessBadge(
                      '${productResult!['totalImported']} products synced '
                      '(${productResult!['newCount']} new)',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: syncing ? null : onSyncOrders,
                    child: const Text('Sync Order History'),
                  ),
                  const SizedBox(width: 12),
                  if (orderResult != null)
                    _SuccessBadge(
                      '${orderResult!['newRecordsImported'] ?? 0} demand records imported',
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Skip if you want to add demand data manually later.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Step3RawMaterials extends StatelessWidget {
  final List<_RmRow> rows;
  final VoidCallback onAddRow;
  final void Function(int) onRemoveRow;

  const _Step3RawMaterials({
    required this.rows,
    required this.onAddRow,
    required this.onRemoveRow,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final suppliers = state.suppliers;

    return _WizardCard(
      title: 'Add Raw Materials',
      subtitle: 'List the materials you use to make your products. '
          'Link each to a supplier.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('No raw materials yet. Add one below.',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ...rows.asMap().entries.map((e) {
            final i = e.key;
            final row = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RmRowWidget(
                row: row,
                suppliers: suppliers,
                onRemove: () => onRemoveRow(i),
              ),
            );
          }),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onAddRow,
            icon: const Icon(Icons.add),
            label: const Text('Add Raw Material'),
          ),
          const SizedBox(height: 8),
          Text('You can also add/edit raw materials later in the Raw Materials page.',
              style:
                  TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _Step4BOM extends StatelessWidget {
  final String? selectedProductId;
  final void Function(String?) onProductChanged;
  final List<_BomRow> bomRows;
  final VoidCallback onAddBomRow;
  final void Function(int) onRemoveBomRow;

  const _Step4BOM({
    required this.selectedProductId,
    required this.onProductChanged,
    required this.bomRows,
    required this.onAddBomRow,
    required this.onRemoveBomRow,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final products = state.products;
    final rawMaterials = state.rawMaterials;

    return _WizardCard(
      title: 'Link Raw Materials to Products (BOM)',
      subtitle: 'Choose a product and specify how much of each raw material '
          'goes into one unit.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: selectedProductId,
            decoration: const InputDecoration(
              labelText: 'Select product',
              border: OutlineInputBorder(),
            ),
            items: products
                .map((p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name),
                    ))
                .toList(),
            onChanged: onProductChanged,
          ),
          const SizedBox(height: 16),
          if (selectedProductId != null) ...[
            if (bomRows.isEmpty)
              Text('Add ingredients below.',
                  style: TextStyle(color: AppColors.textSecondary)),
            ...bomRows.asMap().entries.map((e) {
              final i = e.key;
              final row = e.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BomRowWidget(
                  row: row,
                  rawMaterials: rawMaterials,
                  onRemove: () => onRemoveBomRow(i),
                ),
              );
            }),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onAddBomRow,
              icon: const Icon(Icons.add),
              label: const Text('Add Ingredient'),
            ),
          ],
          const SizedBox(height: 8),
          Text('You can skip this and configure BOMs later in the BOM page.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _Step5Warehouse extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController addressCtrl;
  final TextEditingController cityCtrl;
  final bool saved;
  final VoidCallback onSave;
  final Future<void> Function() onAssign;
  final List<String> assignedProductIds;
  final void Function(List<String>) onAssignedChanged;

  const _Step5Warehouse({
    required this.nameCtrl,
    required this.addressCtrl,
    required this.cityCtrl,
    required this.saved,
    required this.onSave,
    required this.onAssign,
    required this.assignedProductIds,
    required this.onAssignedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return _WizardCard(
      title: 'Set Up a Warehouse',
      subtitle: 'Create a warehouse location and assign products to it.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Warehouse name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: cityCtrl,
            decoration: const InputDecoration(
              labelText: 'City',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: addressCtrl,
            decoration: const InputDecoration(
              labelText: 'Address (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (!saved)
            FilledButton(
              onPressed: onSave,
              child: const Text('Save Warehouse'),
            )
          else ...[
            _SuccessBadge('Warehouse saved'),
            const SizedBox(height: 12),
            Text('Assign products to this warehouse:',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            ...state.products.map((p) {
              final assigned = assignedProductIds.contains(p.id);
              return CheckboxListTile(
                value: assigned,
                title: Text('${p.name} (${p.sku})'),
                subtitle:
                    Text('Stock: ${p.currentStock}'),
                onChanged: (v) {
                  final ids = List<String>.from(assignedProductIds);
                  if (v == true) {
                    ids.add(p.id);
                  } else {
                    ids.remove(p.id);
                  }
                  onAssignedChanged(ids);
                },
              );
            }),
          ],
          const SizedBox(height: 8),
          Text('You can add more warehouses later in the Warehouses page.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _Step6Locations extends StatelessWidget {
  final Map<String, TextEditingController> supplierAddressCtrls;
  final Map<String, TextEditingController> mfrAddressCtrls;

  const _Step6Locations({
    required this.supplierAddressCtrls,
    required this.mfrAddressCtrls,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WizardCard(
          title: 'Supplier Locations',
          subtitle: 'Add addresses for your suppliers.',
          child: Column(
            children: state.suppliers.map((s) {
              supplierAddressCtrls.putIfAbsent(
                s.id, () => TextEditingController(text: s.address ?? ''));
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: supplierAddressCtrls[s.id],
                  decoration: InputDecoration(
                    labelText: s.name,
                    hintText: 'Address',
                    border: const OutlineInputBorder(),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        _WizardCard(
          title: 'Manufacturer Locations',
          subtitle: 'Add addresses for your manufacturers.',
          child: Column(
            children: state.manufacturers.map((m) {
              mfrAddressCtrls.putIfAbsent(
                m.id, () => TextEditingController(text: m.address ?? ''));
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: mfrAddressCtrls[m.id],
                  decoration: InputDecoration(
                    labelText: m.name,
                    hintText: 'Address',
                    border: const OutlineInputBorder(),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Row data models ───────────────────────────────────────────────────────────

class _RmRow {
  final name = TextEditingController();
  final sku = TextEditingController();
  final unitCost = TextEditingController();
  final leadTime = TextEditingController(text: '0');
  String unit = 'units';
  String? selectedSupplierId;

  void dispose() {
    name.dispose();
    sku.dispose();
    unitCost.dispose();
    leadTime.dispose();
  }
}

class _BomRow {
  final qty = TextEditingController(text: '1');
  String? selectedRmId;
  String uom = 'units';

  void dispose() {
    qty.dispose();
  }
}

// ── Shared row widgets ────────────────────────────────────────────────────────

class _RmRowWidget extends StatefulWidget {
  final _RmRow row;
  final List<Supplier> suppliers;
  final VoidCallback onRemove;

  const _RmRowWidget({required this.row, required this.suppliers, required this.onRemove});

  @override
  State<_RmRowWidget> createState() => _RmRowWidgetState();
}

class _RmRowWidgetState extends State<_RmRowWidget> {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: widget.row.name,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: widget.row.sku,
                    decoration: const InputDecoration(
                      labelText: 'SKU',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.row.unitCost,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Unit Cost (EGP)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: widget.row.unit,
                  isDense: true,
                  items: const ['units', 'g', 'kg', 'ml', 'L', 'm', 'cm']
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) => setState(() => widget.row.unit = v ?? 'units'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: widget.row.leadTime,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Lead Time (days)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String?>(
                  value: widget.row.selectedSupplierId,
                  isDense: true,
                  hint: const Text('Supplier'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    ...widget.suppliers.map(
                      (s) => DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => widget.row.selectedSupplierId = v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BomRowWidget extends StatefulWidget {
  final _BomRow row;
  final List<RawMaterial> rawMaterials;
  final VoidCallback onRemove;

  const _BomRowWidget({
    required this.row,
    required this.rawMaterials,
    required this.onRemove,
  });

  @override
  State<_BomRowWidget> createState() => _BomRowWidgetState();
}

class _BomRowWidgetState extends State<_BomRowWidget> {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            value: widget.row.selectedRmId,
            decoration: const InputDecoration(
              labelText: 'Raw Material',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: widget.rawMaterials
                .map((r) => DropdownMenuItem(value: r.id, child: Text(r.name)))
                .toList(),
            onChanged: (v) => setState(() => widget.row.selectedRmId = v),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: TextField(
            controller: widget.row.qty,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Qty',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: widget.row.uom,
          isDense: true,
          items: const ['units', 'g', 'kg', 'ml', 'L', 'm', 'cm']
              .map((u) => DropdownMenuItem(value: u, child: Text(u)))
              .toList(),
          onChanged: (v) => setState(() => widget.row.uom = v ?? 'units'),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: AppColors.error),
          onPressed: widget.onRemove,
        ),
      ],
    );
  }
}

// ── Shared UI helpers ─────────────────────────────────────────────────────────

class _ReadyToGoBanner extends StatelessWidget {
  final VoidCallback onFinish;
  const _ReadyToGoBanner({required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: AppColors.success, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("You're ready to use Ma5zony",
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  'Shopify is connected and your products are imported. '
                  'The remaining steps are optional — you can complete '
                  'them now or anytime later from Settings.',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onFinish,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Go to dashboard'),
          ),
        ],
      ),
    );
  }
}

class _WizardCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _WizardCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _SuccessBadge extends StatelessWidget {
  final String text;
  const _SuccessBadge(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 14, color: AppColors.success),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.success,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StepProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _StepProgressBar({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps, (i) {
        final isActive = i <= currentStep;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < totalSteps - 1 ? 4 : 0),
            height: 4,
            decoration: BoxDecoration(
              color: isActive ? AppColors.primary : AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}
