import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ma5zony/models/app_notification.dart';
import 'package:ma5zony/models/app_user.dart';
import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/models/cash_flow_snapshot.dart';
import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/forecast_result.dart';
import 'package:ma5zony/models/manufacturer.dart';
import 'package:ma5zony/models/manufacturing_recommendation.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/production_order.dart';
import 'package:ma5zony/models/purchase_order.dart';
import 'package:ma5zony/models/raw_material.dart';
import 'package:ma5zony/models/raw_material_order.dart';
import 'package:ma5zony/models/replenishment_recommendation.dart';
import 'package:ma5zony/models/shopify_store_connection.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/models/supplier_order.dart';
import 'package:ma5zony/models/warehouse.dart';
import 'package:ma5zony/models/workflow_log.dart';
import 'package:ma5zony/services/abc_xyz_service.dart';
import 'package:ma5zony/services/cash_flow_service.dart';
import 'package:ma5zony/services/firebase_auth_service.dart';
import 'package:ma5zony/services/firestore_inventory_repository.dart';
import 'package:ma5zony/services/forecasting_service.dart';
import 'package:ma5zony/services/inventory_policy_service.dart';
import 'package:ma5zony/services/inventory_repository.dart';
import 'package:ma5zony/services/manufacturing_service.dart';
import 'package:ma5zony/services/recommendation_engine_service.dart';
import 'package:ma5zony/services/replenishment_service.dart';
import 'package:ma5zony/services/settings_service.dart';
import 'package:ma5zony/services/firebase_shopify_service.dart';
import 'package:ma5zony/services/notification_service.dart';
import 'package:ma5zony/services/workflow_service.dart';
import 'package:ma5zony/models/raw_material_purchase_order.dart';
import 'package:ma5zony/services/backend_api_service.dart';
import 'package:ma5zony/services/minimum_stock_service.dart';
import 'package:ma5zony/services/raw_material_order_service.dart';
import 'package:ma5zony/utils/cloud_function_config.dart';

/// Dedicated notifier for auth state changes only.
/// Used as GoRouter's refreshListenable so the router only re-evaluates
/// when the user actually logs in or out, not on every CRUD notifyListeners().
class AuthNotifier extends ChangeNotifier {
  void notifyAuthChanged() => notifyListeners();
}

/// Thrown when a Cloud Function returns a non-2xx HTTP status.
class CloudFunctionException implements Exception {
  final int statusCode;
  final String message;
  CloudFunctionException(this.statusCode, this.message);
  @override
  String toString() => message;
}

/// Thrown when no Bill of Materials exists for a product during manufacturing
/// approval — lets the UI show a specific, actionable error message.
class BomMissingException implements Exception {
  final String productId;
  BomMissingException(this.productId);
  @override
  String toString() =>
      'No Bill of Materials found for this product. '
      'Please add a BOM before approving a manufacturing recommendation.';
}

/// Central application state ChangeNotifier.
/// Composes all domain services and exposes reactive state to the UI.
class AppState extends ChangeNotifier {
  /// Notifier dedicated to auth state changes for GoRouter refresh.
  final AuthNotifier authNotifier = AuthNotifier();
  // ── Services ───────────────────────────────────────────────────────────────
  InventoryRepository? _repo;
  SettingsService? _settingsService;
  FirebaseShopifyService? _shopifyService;
  NotificationService? _notificationService;
  StreamSubscription<List<AppNotification>>? _notifSub;
  late final ForecastingService _forecastingService;
  late final InventoryPolicyService _policyService;
  late final ReplenishmentService _replenishmentService;
  late final AbcXyzService _abcXyzService;
  late final FirebaseAuthService _authService;
  late final RecommendationEngineService _recEngine;
  late final MinimumStockService _minimumStockService;
  late final RawMaterialOrderService _rmOrderService;
  ManufacturingService? _manufacturingService;
  WorkflowService? _workflowService;
  CashFlowService? _cashFlowService;
  final BackendApiService _backendApi = BackendApiService();

  AppState() {
    _forecastingService = ForecastingService();
    _policyService = InventoryPolicyService();
    _replenishmentService = ReplenishmentService(
      forecastingService: _forecastingService,
      policyService: _policyService,
    );
    _abcXyzService = AbcXyzService();
    _authService = FirebaseAuthService();
    _recEngine = RecommendationEngineService();
    _minimumStockService = MinimumStockService();
    _rmOrderService = RawMaterialOrderService();

    // Listen to Firebase auth state changes and sync our AppUser.
    _authService.authStateChanges.listen(_onAuthStateChanged);
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  /// Initialise Firestore repo once we know the user's uid.
  void _initRepo(String uid) {
    _repo = FirestoreInventoryRepository(uid: uid);
    _settingsService = SettingsService(uid: uid);
    _shopifyService = FirebaseShopifyService(uid: uid);
    _notificationService = NotificationService(uid: uid);
    _manufacturingService = ManufacturingService(repo: _repo!);
    _workflowService = WorkflowService(repo: _repo!);
    _cashFlowService = CashFlowService(repo: _repo!);
    _startNotificationListener();
  }

  // ── Auth State ─────────────────────────────────────────────────────────────
  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;

  String? _authError;
  String? get authError => _authError;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// True while login() or register() is actively handling auth.
  /// Prevents the authStateChanges listener from racing.
  bool _handlingAuth = false;

  void _onAuthStateChanged(dynamic firebaseUser) async {
    // If login() or register() is handling this, skip to avoid race condition.
    if (_handlingAuth) return;

    try {
      if (firebaseUser == null) {
        _currentUser = null;
        _repo = null;
        _settingsService = null;
        _shopifyService = null;
        _clearDomainState();
        authNotifier.notifyAuthChanged();
      } else {
        // Cold start / page reload with existing session.
        if (_currentUser != null && _repo != null) return;
        final profile = await _authService.getUserProfile(firebaseUser.uid);
        if (profile != null) {
          _currentUser = AppUser.fromFirestore(firebaseUser.uid, profile);
        } else {
          _currentUser = AppUser(
            uid: firebaseUser.uid,
            name: firebaseUser.displayName ?? '',
            email: firebaseUser.email ?? '',
            role: 'Inventory Manager',
          );
        }
        _initRepo(firebaseUser.uid);
        notifyListeners();
        authNotifier.notifyAuthChanged();
        await loadAll();
        return;
      }
    } catch (e) {
      _authError = 'Failed to load user profile. Please try again.';
    }
    notifyListeners();
  }

  void _clearDomainState() {
    _notifSub?.cancel();
    _notifSub = null;
    _products = [];
    _warehouses = [];
    _suppliers = [];
    _demandByProduct = {};
    _recommendations = [];
    _currentForecast = null;
    _forecastMapes = {};
    _forecastComparison = {};
    _abcXyzMatrix = {};
    _shopifyConnection = null;
    _settings = const UserSettings();
    _approvedRecommendations = {};
    _notifications = [];
    _teamMembers = [];
    _purchaseOrders = [];
    _supplierOrders = [];
    _rawMaterials = [];
    _boms = [];
    _manufacturers = [];
    _productionOrders = [];
    _rawMaterialOrders = [];
    _mfgRecommendations = [];
    _cashFlowSnapshots = [];
    _workflowLogs = [];
    _minimumStockResults = [];
    _rmPurchaseOrders = [];
    _onboardingComplete = false;
    _onboardingStateLoaded = false;
  }

  Future<bool> login(String email, String password) async {
    _authError = null;
    _handlingAuth = true;
    try {
      final user = await _authService.login(email, password);
      if (user != null) {
        try {
          final profile = await _authService.getUserProfile(user.uid);
          if (profile != null) {
            _currentUser = AppUser.fromFirestore(user.uid, profile);
          } else {
            _currentUser = AppUser(
              uid: user.uid,
              name: user.displayName ?? '',
              email: user.email ?? '',
              role: 'Inventory Manager',
            );
          }
        } catch (_) {
          // Profile fetch may fail on web due to auth propagation delay.
          _currentUser = AppUser(
            uid: user.uid,
            name: user.displayName ?? '',
            email: user.email ?? '',
            role: 'Inventory Manager',
          );
        }
        _initRepo(user.uid);
        notifyListeners();
        authNotifier.notifyAuthChanged();
        await loadAll();
        return true;
      }
      return false;
    } on Exception catch (e) {
      _authError = _parseFirebaseError(e);
      notifyListeners();
      return false;
    } finally {
      _handlingAuth = false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _currentUser = null;
    _repo = null;
    _settingsService = null;
    _shopifyService = null;
    _clearDomainState();
    notifyListeners();
    authNotifier.notifyAuthChanged();
  }

  Future<bool> register(
    String name,
    String email,
    String password,
    String role,
  ) async {
    _authError = null;
    _handlingAuth = true;
    try {
      final user = await _authService.register(
        name: name,
        email: email,
        password: password,
        role: role,
      );
      if (user != null) {
        _currentUser = AppUser(
          uid: user.uid,
          name: name,
          email: email,
          role: role,
        );
        _initRepo(user.uid);
        notifyListeners();
        authNotifier.notifyAuthChanged();
        await loadAll();
        return true;
      }
      return false;
    } on Exception catch (e) {
      _authError = _parseFirebaseError(e);
      notifyListeners();
      return false;
    } finally {
      _handlingAuth = false;
    }
  }

  Future<void> resetPassword(String email) async {
    await _authService.resetPassword(email);
  }

  String _parseFirebaseError(Exception e) {
    final msg = e.toString();
    if (msg.contains('user-not-found')) return 'No account found with that email.';
    if (msg.contains('wrong-password')) return 'Incorrect password.';
    if (msg.contains('invalid-email')) return 'Invalid email address.';
    if (msg.contains('email-already-in-use')) return 'An account already exists with that email.';
    if (msg.contains('weak-password')) return 'Password must be at least 6 characters.';
    if (msg.contains('invalid-credential')) return 'Invalid email or password.';
    if (msg.contains('INVALID_LOGIN_CREDENTIALS')) return 'Invalid email or password.';
    if (msg.contains('too-many-requests')) return 'Too many attempts. Please try again later.';
    if (msg.contains('network-request-failed')) return 'Network error. Check your connection.';
    return 'Authentication failed. Please try again.';
  }

  // ── Domain State ───────────────────────────────────────────────────────────
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<Product> _products = [];
  List<Warehouse> _warehouses = [];
  List<Supplier> _suppliers = [];
  Map<String, List<DomainDemandRecord>> _demandByProduct = {};
  List<ReplenishmentRecommendation> _recommendations = [];
  ForecastResult? _currentForecast;

  /// Persisted MAPE values keyed by productId, loaded at startup and updated
  /// whenever a forecast is run. Used to compute the global forecast accuracy KPI.
  Map<String, double> _forecastMapes = {};

  /// Side-by-side forecast comparison (SMA / SES / Holt / HoltWinters / WMA)
  /// produced by [compareForecastAlgorithms]. Map key = algorithm name.
  Map<String, ForecastResult> _forecastComparison = {};

  /// ABC-XYZ classification matrix (productId → ProductClassification).
  /// Populated by [classifyProducts] or [runFullPipeline].
  Map<String, ProductClassification> _abcXyzMatrix = {};
  ShopifyStoreConnection? _shopifyConnection;
  UserSettings _settings = const UserSettings();
  ThemeMode _themeMode = ThemeMode.light;
  Set<String> _approvedRecommendations = {};
  List<AppUser> _teamMembers = [];
  List<PurchaseOrder> _purchaseOrders = [];
  List<SupplierOrder> _supplierOrders = [];
  // Tracks how many emails were sent during the last approval operation.
  // Read by the UI to construct the success snackbar.
  int _lastApprovalEmailsSent = 0;

  // Supply-chain state (Phase 1–3)
  List<RawMaterial> _rawMaterials = [];
  List<BillOfMaterials> _boms = [];
  List<Manufacturer> _manufacturers = [];
  List<ProductionOrder> _productionOrders = [];
  List<RawMaterialOrder> _rawMaterialOrders = [];
  List<ManufacturingRecommendation> _mfgRecommendations = [];
  List<CashFlowSnapshot> _cashFlowSnapshots = [];
  List<WorkflowLog> _workflowLogs = [];
  List<MinimumStockResult> _minimumStockResults = [];
  List<RawMaterialPurchaseOrder> _rmPurchaseOrders = [];
  bool _onboardingComplete = false;
  bool _onboardingStateLoaded = false;
  List<Product> get products => _products;
  List<Warehouse> get warehouses => _warehouses;
  List<Supplier> get suppliers => _suppliers;
  Map<String, List<DomainDemandRecord>> get demandByProduct => _demandByProduct;
  List<ReplenishmentRecommendation> get recommendations => _recommendations;
  ForecastResult? get currentForecast => _currentForecast;
  Map<String, ForecastResult> get forecastComparison => _forecastComparison;

  void clearCurrentForecast() {
    _currentForecast = null;
    notifyListeners();
  }

  Map<String, ProductClassification> get abcXyzMatrix => _abcXyzMatrix;
  ShopifyStoreConnection? get shopifyConnection => _shopifyConnection;
  UserSettings get settings => _settings;
  ThemeMode get themeMode => _themeMode;
  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
  Set<String> get approvedRecommendations => _approvedRecommendations;
  int get lastApprovalEmailsSent => _lastApprovalEmailsSent;
  List<AppUser> get teamMembers => _teamMembers;
  List<PurchaseOrder> get purchaseOrders => _purchaseOrders;
  List<SupplierOrder> get supplierOrders => _supplierOrders;

  // Supply-chain getters
  List<RawMaterial> get rawMaterials => _rawMaterials;
  List<BillOfMaterials> get boms => _boms;
  List<Manufacturer> get manufacturers => _manufacturers;
  List<ProductionOrder> get productionOrders => _productionOrders;
  List<RawMaterialOrder> get rawMaterialOrders => _rawMaterialOrders;
  List<ManufacturingRecommendation> get mfgRecommendations => _mfgRecommendations;
  List<CashFlowSnapshot> get cashFlowSnapshots => _cashFlowSnapshots;
  CashFlowSnapshot? get latestCashFlow =>
      _cashFlowSnapshots.isNotEmpty ? _cashFlowSnapshots.first : null;
  List<WorkflowLog> get workflowLogs => _workflowLogs;
  List<MinimumStockResult> get minimumStockResults => _minimumStockResults;
  List<MinimumStockResult> get criticalStockProducts =>
      _minimumStockResults.where((r) => r.isUrgent).toList();
  bool get hasUrgentStockAlerts => _minimumStockResults.any((r) => r.isUrgent);
  List<RawMaterialPurchaseOrder> get rmPurchaseOrders => _rmPurchaseOrders;
  bool get onboardingComplete => _onboardingComplete;
  bool get onboardingStateLoaded => _onboardingStateLoaded;

  // ── Notifications ──────────────────────────────────────────────────────────
  List<AppNotification> _notifications = [];
  List<AppNotification> get notifications => _notifications;
  int get unreadNotificationCount =>
      _notifications.where((n) => !n.isRead).length;

  // ── Product CRUD ───────────────────────────────────────────────────────────

  Future<void> addProduct(Product product) async {
    try {
      final saved = await _repo!.addProduct(product);
      _products.add(saved);
      _rebuildRecommendations();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to add product: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateProduct(Product product) async {
    try {
      await _repo!.updateProduct(product);
      final idx = _products.indexWhere((p) => p.id == product.id);
      if (idx != -1) _products[idx] = product;
      _rebuildRecommendations();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to update product: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Bulk-assign a set of products to a warehouse (or pass null to unassign).
  /// Used by the Warehouse → "Manage Products" workflow.
  Future<void> assignProductsToWarehouse(
    String? warehouseId,
    List<String> productIds,
  ) async {
    if (productIds.isEmpty) return;
    try {
      for (final pid in productIds) {
        final idx = _products.indexWhere((p) => p.id == pid);
        if (idx == -1) continue;
        final p = _products[idx];
        if (p.warehouseId == warehouseId) continue;
        final updated = Product(
          id: p.id,
          sku: p.sku,
          name: p.name,
          category: p.category,
          unitCost: p.unitCost,
          currentStock: p.currentStock,
          supplierId: p.supplierId,
          manufacturerId: p.manufacturerId,
          warehouseId: warehouseId,
          isActive: p.isActive,
          leadTimeDays: p.leadTimeDays,
        );
        await _repo!.updateProduct(updated);
        _products[idx] = updated;
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to assign products: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteProduct(String productId) async {
    try {
      // Cascade: delete associated demand records
      final records = _demandByProduct[productId] ?? [];
      for (final r in records) {
        await _repo!.deleteDemandRecord(r.id);
      }
      // Cascade: delete associated BOM entries
      final productBoms = _boms.where((b) => b.finalProductId == productId).toList();
      for (final bom in productBoms) {
        await _repo!.deleteBOM(bom.id);
      }
      _boms.removeWhere((b) => b.finalProductId == productId);
      await _repo!.deleteProduct(productId);
      _products.removeWhere((p) => p.id == productId);
      _demandByProduct.remove(productId);
      _rebuildRecommendations();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to delete product: $e';
      notifyListeners();
      rethrow;
    }
  }

  // ── Supplier CRUD ──────────────────────────────────────────────────────────

  Future<void> addSupplier(Supplier supplier) async {
    try {
      final saved = await _repo!.addSupplier(supplier);
      _suppliers.add(saved);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to add supplier: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateSupplier(Supplier supplier) async {
    try {
      await _repo!.updateSupplier(supplier);
      final idx = _suppliers.indexWhere((s) => s.id == supplier.id);
      if (idx != -1) _suppliers[idx] = supplier;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to update supplier: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteSupplier(String supplierId) async {
    try {
      // Cascade: null out supplierId on linked products
      for (var i = 0; i < _products.length; i++) {
        if (_products[i].supplierId == supplierId) {
          final updated = Product(
            id: _products[i].id,
            sku: _products[i].sku,
            name: _products[i].name,
            category: _products[i].category,
            unitCost: _products[i].unitCost,
            currentStock: _products[i].currentStock,
            supplierId: null,
            manufacturerId: _products[i].manufacturerId,
            warehouseId: _products[i].warehouseId,
            isActive: _products[i].isActive,
            leadTimeDays: _products[i].leadTimeDays,
          );
          await _repo!.updateProduct(updated);
          _products[i] = updated;
        }
      }
      // Cascade: null out supplierId on linked raw materials
      for (var i = 0; i < _rawMaterials.length; i++) {
        if (_rawMaterials[i].supplierId == supplierId) {
          final rm = _rawMaterials[i];
          final updated = RawMaterial(
            id: rm.id,
            name: rm.name,
            sku: rm.sku,
            unit: rm.unit,
            unitOfMeasure: rm.unitOfMeasure,
            unitCost: rm.unitCost,
            supplierId: null,
            currentStock: rm.currentStock,
            safetyStock: rm.safetyStock,
            leadTimeDays: rm.leadTimeDays,
          );
          await _repo!.updateRawMaterial(updated);
          _rawMaterials[i] = updated;
        }
      }
      await _repo!.deleteSupplier(supplierId);
      _suppliers.removeWhere((s) => s.id == supplierId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to delete supplier: $e';
      notifyListeners();
      rethrow;
    }
  }

  // ── Warehouse CRUD ─────────────────────────────────────────────────────────

  Future<void> addWarehouse(Warehouse warehouse) async {
    try {
      final saved = await _repo!.addWarehouse(warehouse);
      _warehouses.add(saved);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to add warehouse: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<Warehouse?> addWarehouseAndReturn(Warehouse warehouse) async {
    try {
      final saved = await _repo!.addWarehouse(warehouse);
      _warehouses.add(saved);
      notifyListeners();
      return saved;
    } catch (e) {
      _errorMessage = 'Failed to add warehouse: $e';
      notifyListeners();
      return null;
    }
  }

  Future<void> updateWarehouse(Warehouse warehouse) async {
    try {
      await _repo!.updateWarehouse(warehouse);
      final idx = _warehouses.indexWhere((w) => w.id == warehouse.id);
      if (idx != -1) _warehouses[idx] = warehouse;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to update warehouse: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteWarehouse(String warehouseId) async {
    try {
      // Unassign all products from this warehouse before deleting.
      for (var i = 0; i < _products.length; i++) {
        if (_products[i].warehouseId == warehouseId) {
          final updated = Product(
            id: _products[i].id,
            sku: _products[i].sku,
            name: _products[i].name,
            category: _products[i].category,
            unitCost: _products[i].unitCost,
            currentStock: _products[i].currentStock,
            supplierId: _products[i].supplierId,
            manufacturerId: _products[i].manufacturerId,
            warehouseId: null,
            isActive: _products[i].isActive,
            leadTimeDays: _products[i].leadTimeDays,
          );
          await _repo!.updateProduct(updated);
          _products[i] = updated;
        }
      }
      await _repo!.deleteWarehouse(warehouseId);
      _warehouses.removeWhere((w) => w.id == warehouseId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to delete warehouse: $e';
      notifyListeners();
      rethrow;
    }
  }

  // ── Demand Record CRUD ─────────────────────────────────────────────────────

  Future<void> addDemandRecord(DomainDemandRecord record) async {
    try {
      final saved = await _repo!.addDemandRecord(record);
      _demandByProduct.putIfAbsent(saved.productId, () => []).add(saved);
      _rebuildRecommendations();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to add demand record: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addDemandRecordsBatch(List<DomainDemandRecord> records) async {
    try {
      for (final record in records) {
        final saved = await _repo!.addDemandRecord(record);
        _demandByProduct.putIfAbsent(saved.productId, () => []).add(saved);
      }
      _rebuildRecommendations();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to import demand records: $e';
      notifyListeners();
      rethrow;
    }
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  Future<void> loadSettings() async {
    if (_settingsService == null) return;
    _settings = await _settingsService!.load();
    notifyListeners();
  }

  Future<void> saveSettings(UserSettings updated) async {
    if (_settingsService == null) return;
    await _settingsService!.save(updated);
    _settings = updated;
    notifyListeners();
  }

  // ── Replenishment Approval ─────────────────────────────────────────────────

  /// Approves a replenishment recommendation by automatically creating a
  /// confirmed [PurchaseOrder], creating the corresponding [SupplierOrder],
  /// and sending the supplier email via Cloud Function.
  ///
  /// Throws [CloudFunctionException] if the email call fails, so the UI can
  /// show a differentiated warning while still accepting the approval.
  Future<void> approveRecommendation(ReplenishmentRecommendation rec) async {
    if (_repo == null || _currentUser == null) return;

    _lastApprovalEmailsSent = 0;

    // Build a one-item PurchaseOrder for this recommendation.
    final product = _products.where((p) => p.id == rec.productId).firstOrNull;
    final supplierId = product?.supplierId;
    final supplier = supplierId != null
        ? _suppliers.where((s) => s.id == supplierId).firstOrNull
        : null;

    final item = PurchaseOrderItem(
      productId: rec.productId,
      productName: rec.productName,
      sku: rec.sku,
      quantity: rec.suggestedOrderQty,
      unitCost: product?.unitCost ?? 0,
      supplierId: supplierId,
      supplierName: supplier?.name,
      supplierEmail: supplier?.contactEmail,
    );

    final draft = PurchaseOrder(
      id: '',
      status: OrderStatus.draft,
      createdAt: DateTime.now(),
      createdByUid: _currentUser!.uid,
      createdByName: _currentUser!.name,
      items: [item],
    );

    // Create PO + SupplierOrders.
    final po = await confirmPurchaseOrder(draft);

    if (po != null && (supplier?.contactEmail.isNotEmpty ?? false)) {
      // Mark as sent and send supplier emails.
      await _invokeCloudFunction(
        CloudFunctionConfig.sendSupplierEmails,
        {'uid': _currentUser!.uid, 'purchaseOrderId': po.id},
      );
      _lastApprovalEmailsSent = 1;
    }

    // Atomically update PO status + record approval in a single batch.
    final batch = FirebaseFirestore.instance.batch();

    if (po != null) {
      final poRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('purchaseOrders')
          .doc(po.id);
      final newStatus = (supplier?.contactEmail.isNotEmpty ?? false)
          ? 'sent'
          : 'confirmed';
      batch.update(poRef, {'status': newStatus});
      po.status = newStatus == 'sent' ? OrderStatus.sent : OrderStatus.confirmed;
    }

    final approvalRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('approvals')
        .doc(rec.productId);
    batch.set(approvalRef, {
      'productId': rec.productId,
      'productName': rec.productName,
      'sku': rec.sku,
      'suggestedOrderQty': rec.suggestedOrderQty,
      'purchaseOrderId': po?.id,
      'approvedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    _approvedRecommendations.add(rec.productId);
    notifyListeners();
  }

  /// Approve a replenishment recommendation for a *manufactured* product.
  /// Reads the product's BOM, calculates raw material needs, creates a
  /// ProductionOrder + RawMaterialOrders, and notifies factory/manufacturer.
  Future<ProductionOrder?> approveReplenishmentManufacture(
    ReplenishmentRecommendation rec,
  ) async {
    if (_currentUser == null || _manufacturingService == null || _workflowService == null) {
      return null;
    }

    _lastApprovalEmailsSent = 0;

    final product = _products.where((p) => p.id == rec.productId).firstOrNull;
    final manufacturerId = product?.manufacturerId ?? '';
    if (manufacturerId.isEmpty) {
      throw Exception(
        'Product "${rec.productName}" has no manufacturer assigned. '
        'Assign one in Products → Edit.',
      );
    }

    final bom = _boms.where((b) => b.finalProductId == rec.productId).firstOrNull;
    if (bom == null) throw BomMissingException(rec.productId);

    final estimatedCost = bom.materials.fold<double>(0.0, (acc, mat) {
      final rm = _rawMaterials.where((r) => r.id == mat.rawMaterialId).firstOrNull;
      return acc + (rm?.unitCost ?? 0) * mat.quantityPerUnit * rec.suggestedOrderQty;
    });

    // Create ProductionOrder.
    final order = await _manufacturingService!.createProductionOrder(
      finalProductId: rec.productId,
      quantity: rec.suggestedOrderQty,
      manufacturerId: manufacturerId,
      estimatedCost: estimatedCost,
    );
    _productionOrders.insert(0, order);

    // Generate RawMaterialOrders from BOM.
    final rmOrders = await _manufacturingService!.generateRawMaterialOrders(
      productionOrder: order,
      bom: bom,
      rawMaterials: _rawMaterials,
    );
    _rawMaterialOrders.addAll(rmOrders);

    // Create per-supplier factory orders + send factory emails.
    final supplierCount = await _createPerSupplierFactoryOrders(order, rmOrders);

    int emailsSent = 0;
    if (supplierCount > 0) {
      try {
        final result = await _invokeCloudFunction(
          CloudFunctionConfig.sendFactoryEmails,
          {'uid': _currentUser!.uid, 'productionOrderId': order.id},
        );
        final results = (result['results'] as List<dynamic>?) ?? [];
        emailsSent += results.where((r) => (r as Map)['status'] == 'sent').length;
      } catch (_) {}
    }

    // Transition to materialsOrdered.
    await _workflowService!.transitionProductionOrder(
      order,
      ProductionOrderStatus.materialsOrdered,
      _currentUser!.uid,
    );

    // Create manufacturer portal doc + send manufacturer email.
    await _createManufacturerPortalOrderAtApproval(order, rmOrders);
    try {
      final mfrResult = await _invokeCloudFunction(
        CloudFunctionConfig.sendManufacturerEmails,
        {'uid': _currentUser!.uid, 'productionOrderId': order.id},
      );
      final mfrResults = (mfrResult['results'] as List<dynamic>?) ?? [];
      emailsSent += mfrResults.where((r) => (r as Map)['status'] == 'sent').length;
    } catch (_) {}

    // Record approval.
    final approvalRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('approvals')
        .doc(rec.productId);
    await approvalRef.set({
      'productId': rec.productId,
      'productName': rec.productName,
      'sku': rec.sku,
      'suggestedOrderQty': rec.suggestedOrderQty,
      'productionOrderId': order.id,
      'approvedAt': FieldValue.serverTimestamp(),
    });

    _approvedRecommendations.add(rec.productId);
    _lastApprovalEmailsSent = emailsSent;
    notifyListeners();
    return order;
  }

  // ── Notifications ──────────────────────────────────────────────────────────

  void _startNotificationListener() {
    _notifSub?.cancel();
    _notifSub = _notificationService?.stream().listen((list) {
      _notifications = list;
      notifyListeners();
    });
  }

  Future<void> markNotificationRead(String notifId) async {
    await _notificationService?.markRead(notifId);
  }

  Future<void> markAllNotificationsRead() async {
    await _notificationService?.markAllRead();
  }

  Future<void> deleteNotification(String notifId) async {
    await _notificationService?.delete(notifId);
  }

  /// Checks all products and generates low-stock / stockout notifications.
  Future<void> _checkStockAlerts() async {
    if (_notificationService == null) return;
    for (final rec in _recommendations) {
      final product =
          _products.where((p) => p.id == rec.productId).firstOrNull;
      if (product == null) continue;
      if (product.currentStock == 0) {
        await _notificationService!.notifyStockout(product.name);
      } else if (rec.status == 'Order Now' || rec.status == 'Critical') {
        await _notificationService!
            .notifyLowStock(product.name, product.currentStock);
      }
    }
  }

  // ── Team Management ────────────────────────────────────────────────────────

  /// Load team members (for owners).
  Future<void> loadTeamMembers() async {
    if (_currentUser == null || _currentUser!.role != 'SME Owner') return;
    final rawList = await _authService.getTeamMembers(_currentUser!.uid);
    _teamMembers = rawList
        .map((data) => AppUser.fromFirestore(data['uid'] as String, data))
        .toList();
    notifyListeners();
  }

  /// Invite an Inventory Manager by email.
  Future<String> inviteTeamMember(String email) async {
    if (_currentUser == null) return 'Not authenticated.';
    final result =
        await _authService.inviteTeamMember(_currentUser!.uid, email);
    if (result == 'added') {
      await loadTeamMembers();
    }
    return result;
  }

  /// Remove a team member.
  Future<void> removeTeamMember(String memberUid) async {
    await _authService.removeTeamMember(memberUid);
    _teamMembers.removeWhere((m) => m.uid == memberUid);
    notifyListeners();
  }

  // ── Computed KPIs ──────────────────────────────────────────────────────────

  /// Total inventory value = Σ(currentStock × unitCost)
  double get totalStockValue =>
      _products.fold(0, (acc, p) => acc + (p.currentStock * p.unitCost));

  /// Number of products below minimum stock level (critically low).
  int get lowStockItems => _minimumStockResults.isEmpty
      ? _recommendations.length
      : _minimumStockResults.where((r) => r.isUrgent).length;

  /// Open replenishment recommendations count (excludes already-approved ones).
  int get openRecommendations => _recommendations
      .where((r) => !_approvedRecommendations.contains(r.productId))
      .length;

  /// Forecast accuracy = 1 – average MAPE across all products that have been
  /// forecast (loaded from Firestore at startup). Falls back to the current
  /// in-session forecast when no persisted results exist yet.
  double get forecastAccuracy {
    if (_forecastMapes.isNotEmpty) {
      final avgMape =
          _forecastMapes.values.reduce((a, b) => a + b) / _forecastMapes.length;
      return (1 - avgMape).clamp(0.0, 1.0);
    }
    if (_currentForecast?.mape != null) return 1 - _currentForecast!.mape!;
    return 0.0;
  }

  // ── Load All Data ──────────────────────────────────────────────────────────

  Future<void> loadAll() async {
    _isLoading = true;
    notifyListeners();

    if (_repo == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final results = await Future.wait([
        _repo!.getProducts(),
        _repo!.getWarehouses(),
        _repo!.getSuppliers(),
        _repo!.getDemandHistory(),
      ]);

      _products = results[0] as List<Product>;
      _warehouses = results[1] as List<Warehouse>;
      _suppliers = results[2] as List<Supplier>;
      _demandByProduct = results[3] as Map<String, List<DomainDemandRecord>>;

      await loadSettings();

      // Load Shopify connection state
      await _loadShopifyConnection();

      // Load approvals
      if (_currentUser != null) {
        final approvalSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('approvals')
            .get();
        _approvedRecommendations = approvalSnap.docs.map((d) => d.id).toSet();
      }

      _rebuildRecommendations();

      // Load team members for owners
      await loadTeamMembers();

      // Load purchase orders
      await loadPurchaseOrders();

      // Load supply-chain data in parallel
      await loadManufacturingData();

      // Load onboarding state
      await loadOnboardingState();

      // Check for stock alerts (fire-and-forget)
      _checkStockAlerts();

      // Load persisted MAPE values so forecastAccuracy KPI is meaningful on startup.
      unawaited(_loadForecastMapes());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Forecasting ────────────────────────────────────────────────────────────

  Future<void> runForecast(
    String productId,
    String algorithm,
    int smaWindow,
    double alpha, {
    double beta = 0.1,
    double gamma = 0.2,
    List<double> wmaWeights = const [1, 2, 3],
    int seasonLength = 12,
  }) async {
    // Try backend first
    try {
      final result = await _backendApi.runForecast(
        productId: productId,
        method: algorithm,
        windowSize: algorithm == 'SMA' ? smaWindow : null,
        alpha: (algorithm == 'SES' || algorithm == 'Holt' || algorithm == 'HoltWinters') ? alpha : null,
      );
      _currentForecast = ForecastResult.fromJson(result);
      await _persistForecastResult(_currentForecast!);
      notifyListeners();
      return;
    } catch (_) {
      // Backend unavailable — fall back to local
    }

    final records = _demandByProduct[productId] ?? [];
    if (records.isEmpty) {
      throw Exception(
          'No demand data found for this product. Add demand records first via the Demand Data screen.');
    }

    // Resolve lead time: product-level > supplier > 0
    final product = _products.where((p) => p.id == productId).firstOrNull;
    int effectiveLeadTimeDays = product?.leadTimeDays ?? 0;
    if (effectiveLeadTimeDays == 0 && product?.supplierId != null) {
      final supplier =
          _suppliers.where((s) => s.id == product!.supplierId).firstOrNull;
      effectiveLeadTimeDays = supplier?.typicalLeadTimeDays ?? 0;
    }

    final sorted = [...records]
      ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
    final periods = sorted.map((r) => r.periodStart).toList();
    final demand = sorted.map((r) => r.quantity.toDouble()).toList();

    _currentForecast = _forecastingService.generateForecast(
      productId: productId,
      periods: periods,
      demand: demand,
      algorithm: algorithm,
      smaWindow: smaWindow,
      alpha: alpha,
      beta: beta,
      gamma: gamma,
      wmaWeights: wmaWeights,
      seasonLength: seasonLength,
      leadTimeDays: effectiveLeadTimeDays,
    );

    if (_currentForecast != null) {
      await _persistForecastResult(_currentForecast!);
    }
    notifyListeners();
  }

  /// Writes the latest forecast result to
  /// `users/{uid}/forecastResults/{productId}` so it can be rehydrated when the
  /// user returns to the Forecasts screen (e.g. from a dashboard deep-link).
  /// Failures are swallowed — persistence is best-effort and never blocks UI.
  Future<void> _persistForecastResult(ForecastResult result) async {
    if (_currentUser == null) return;
    try {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('forecastResults')
          .doc(result.productId);
      await ref.set({
        ...result.toJson(),
        'computedAt': FieldValue.serverTimestamp(),
      });
      // Keep in-memory MAPE cache in sync so forecastAccuracy updates immediately.
      if (result.mape != null) {
        _forecastMapes[result.productId] = result.mape!;
        notifyListeners();
      }
    } catch (_) {
      // Best-effort persistence; non-fatal.
    }
  }

  /// Loads MAPE values for all persisted forecast results at startup so that
  /// the forecastAccuracy KPI is meaningful without requiring a fresh run.
  Future<void> _loadForecastMapes() async {
    if (_currentUser == null) return;
    try {
      final snaps = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('forecastResults')
          .get();
      for (final doc in snaps.docs) {
        final mape = (doc.data()['mape'] as num?)?.toDouble();
        if (mape != null) _forecastMapes[doc.id] = mape;
      }
    } catch (_) {
      // Non-fatal — KPI will show N/A if Firestore is unavailable.
    }
  }

  /// Loads the most recently persisted forecast for [productId] (if any) and
  /// sets it as the current forecast. Returns true when a result was loaded.
  Future<bool> loadLatestForecast(String productId) async {
    if (_currentUser == null) return false;
    try {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('forecastResults')
          .doc(productId);
      final snap = await ref.get();
      if (!snap.exists) return false;
      final data = snap.data();
      if (data == null) return false;
      // Strip the serverTimestamp so fromJson doesn't try to parse it.
      final json = Map<String, dynamic>.from(data)..remove('computedAt');
      _currentForecast = ForecastResult.fromJson(json);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Runs every supported forecasting algorithm against the given product's
  /// demand history and stores the results in [forecastComparison] so the UI
  /// can render a side-by-side comparison (with MAPE/RMSE per method).
  Future<void> compareForecastAlgorithms(String productId) async {
    final records = _demandByProduct[productId] ?? [];
    if (records.isEmpty) {
      _forecastComparison = {};
      notifyListeners();
      return;
    }

    final sorted = [...records]
      ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
    final periods = sorted.map((r) => r.periodStart).toList();
    final demand = sorted.map((r) => r.quantity.toDouble()).toList();

    final results = <String, ForecastResult>{};

    // SMA(3)
    if (demand.length >= 3) {
      results['SMA'] = _forecastingService.generateForecast(
        productId: productId,
        periods: periods,
        demand: demand,
        algorithm: 'SMA',
        smaWindow: 3,
      );
    }
    // WMA(1,2,3)
    if (demand.length >= 3) {
      results['WMA'] = _forecastingService.generateForecast(
        productId: productId,
        periods: periods,
        demand: demand,
        algorithm: 'WMA',
        wmaWeights: const [1, 2, 3],
      );
    }
    // SES(α=0.3)
    if (demand.isNotEmpty) {
      results['SES'] = _forecastingService.generateForecast(
        productId: productId,
        periods: periods,
        demand: demand,
        algorithm: 'SES',
        alpha: 0.3,
      );
    }
    // Holt
    if (demand.length >= 2) {
      results['Holt'] = _forecastingService.generateForecast(
        productId: productId,
        periods: periods,
        demand: demand,
        algorithm: 'Holt',
        alpha: 0.3,
        beta: 0.1,
      );
    }
    // Holt-Winters (needs 2+ seasonal cycles; default 12-month season)
    if (demand.length >= 24) {
      results['HoltWinters'] = _forecastingService.generateForecast(
        productId: productId,
        periods: periods,
        demand: demand,
        algorithm: 'HoltWinters',
        alpha: 0.3,
        beta: 0.1,
        gamma: 0.1,
        seasonLength: 12,
      );
    }

    _forecastComparison = results;
    notifyListeners();
  }

  // ── ABC-XYZ Classification ─────────────────────────────────────────────────

  /// Rebuilds the ABC-XYZ classification matrix from the current products
  /// and demand history. Exposed via [abcXyzMatrix].
  void classifyProducts() {
    _abcXyzMatrix = _abcXyzService.buildMatrix(
      products: _products,
      demandByProduct: _demandByProduct,
    );
    notifyListeners();
  }

  /// Summary counts per cell of the 9-cell matrix (e.g. {"AX": 5, "BY": 12}).
  Map<String, int> get abcXyzSummary =>
      _abcXyzService.matrixSummary(_abcXyzMatrix);

  // ── Full Pipeline ──────────────────────────────────────────────────────────

  /// Orchestrates the end-to-end decision-support pipeline:
  /// 1. Refresh demand history from the repository
  /// 2. Run ABC-XYZ classification
  /// 3. Rebuild replenishment recommendations (uses best forecast per product)
  ///
  /// This is the single entry point called after a Shopify import or a manual
  /// demand-data update. It is safe to call repeatedly.
  Future<void> runFullPipeline() async {
    if (_repo == null) return;
    _isLoading = true;
    notifyListeners();
    try {
      _demandByProduct = await _repo!.getDemandHistory();
      classifyProducts();
      _rebuildRecommendations();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Replenishment ──────────────────────────────────────────────────────────

  void _rebuildRecommendations() {
    final supplierMap = {for (final s in _suppliers) s.id: s};
    _recommendations = _replenishmentService.buildRecommendations(
      products: _products,
      demandByProduct: _demandByProduct,
      suppliers: supplierMap,
      settings: _settings,
    );
    // Keep ABC-XYZ classification in sync with the latest demand + product set
    // so the matrix is always available without needing a manual refresh.
    _abcXyzMatrix = _abcXyzService.buildMatrix(
      products: _products,
      demandByProduct: _demandByProduct,
    );
    computeMinimumStockLevels();
  }

  void computeMinimumStockLevels() {
    _minimumStockResults = _minimumStockService.computeAll(
      products: _products,
      demandByProduct: _demandByProduct,
      boms: _boms,
      rawMaterials: _rawMaterials,
      suppliers: _suppliers,
      manufacturers: _manufacturers,
      settings: _settings,
    );
  }

  // ── Shopify ────────────────────────────────────────────────────────────────

  /// Returns the OAuth URL the UI should open in a browser.
  /// After the user approves, call [waitForShopifyConnection] to poll.
  Future<String?> getShopifyOAuthUrl(String shopDomain) async {
    if (_shopifyService == null) return null;
    return _shopifyService!.getOAuthUrl(shopDomain);
  }

  /// Polls Firestore until the OAuth callback writes the connection doc.
  Future<void> connectShopify(String shopDomain) async {
    if (_shopifyService == null) return;
    _shopifyConnection = await _shopifyService!.connectStore(
      shopDomain: shopDomain,
    );
    notifyListeners();
  }

  Future<void> disconnectShopify() async {
    if (_shopifyService == null) {
      _shopifyConnection = null;
      notifyListeners();
      return;
    }
    await _shopifyService!.disconnectStore();
    _shopifyConnection = null;
    notifyListeners();
  }

  /// Imports products from Shopify with SKU-based deduplication.
  /// Returns a summary: {newCount, mergedCount, totalImported}.
  Future<Map<String, int>> importShopifyProducts() async {
    if (_shopifyService == null) return {'newCount': 0, 'mergedCount': 0, 'totalImported': 0};
    final imported = await _shopifyService!.importProductsFromShopify();
    int newCount = 0;
    int mergedCount = 0;

    for (final p in imported) {
      // 1. Try matching by SKU first (handles locally-created products)
      final skuIdx = p.sku.isNotEmpty
          ? _products.indexWhere((e) => e.sku == p.sku && e.id != p.id)
          : -1;
      // 2. Fall back to matching by ID
      final idIdx = _products.indexWhere((e) => e.id == p.id);

      if (skuIdx != -1) {
        // SKU match found — merge: update stock from Shopify, keep local links
        final existing = _products[skuIdx];
        _products[skuIdx] = Product(
          id: existing.id,
          sku: existing.sku,
          name: existing.name.isNotEmpty ? existing.name : p.name,
          category: existing.category.isNotEmpty ? existing.category : p.category,
          unitCost: existing.unitCost > 0 ? existing.unitCost : p.unitCost,
          currentStock: p.currentStock, // Shopify is source of truth for stock
          supplierId: existing.supplierId,
          manufacturerId: existing.manufacturerId,
          warehouseId: existing.warehouseId,
          isActive: existing.isActive,
        );
        mergedCount++;
      } else if (idIdx != -1) {
        // Same Shopify ID — re-import, keep local links
        final existing = _products[idIdx];
        _products[idIdx] = Product(
          id: existing.id,
          sku: p.sku.isNotEmpty ? p.sku : existing.sku,
          name: p.name.isNotEmpty ? p.name : existing.name,
          category: p.category.isNotEmpty ? p.category : existing.category,
          unitCost: p.unitCost > 0 ? p.unitCost : existing.unitCost,
          currentStock: p.currentStock,
          supplierId: existing.supplierId ?? p.supplierId,
          manufacturerId: existing.manufacturerId ?? p.manufacturerId,
          warehouseId: existing.warehouseId ?? p.warehouseId,
          isActive: existing.isActive,
        );
        mergedCount++;
      } else {
        // New product
        _products.add(p);
        newCount++;
      }
    }
    _rebuildRecommendations();
    notifyListeners();
    return {
      'newCount': newCount,
      'mergedCount': mergedCount,
      'totalImported': imported.length,
    };
  }

  Future<void> syncShopifyInventory() async {
    if (_shopifyService == null) return;
    await _shopifyService!.syncInventoryFromShopify();
    // Reload products to get updated stock levels.
    if (_repo != null) {
      _products = await _repo!.getProducts();
      _rebuildRecommendations();
    }
    _shopifyConnection = await _shopifyService!.getCurrentConnection();
    notifyListeners();
  }

  /// Fetches available products from the Shopify store for the import dialog.
  Future<List<Product>> fetchShopifyProducts() async {
    if (_shopifyService == null) return [];
    return _shopifyService!.fetchShopifyProducts();
  }

  /// Imports Shopify order history as demand records.
  /// Returns info map with totalOrders, newRecordsImported, skippedDuplicates.
  Future<Map<String, dynamic>?> importShopifyOrders() async {
    if (_shopifyService == null) return null;
    final result = await _shopifyService!.importOrderHistory();
    // Reload demand data to pick up new records
    if (_repo != null) {
      _demandByProduct = await _repo!.getDemandHistory();
      _rebuildRecommendations();
    }
    // Notify about the import
    final imported = result['newRecordsImported'] as int? ?? 0;
    if (imported > 0) {
      await _notificationService?.notifyShopifySync(imported);
    }
    notifyListeners();
    return result;
  }

  /// Loads Shopify connection state from Firestore.
  Future<void> _loadShopifyConnection() async {
    if (_shopifyService == null) return;
    _shopifyConnection = await _shopifyService!.getCurrentConnection();
  }

  // ── Purchase Order Management ──────────────────────────────────────────────

  FirestoreInventoryRepository? get _firestoreRepo =>
      _repo is FirestoreInventoryRepository
          ? _repo as FirestoreInventoryRepository
          : null;

  Future<void> loadPurchaseOrders() async {
    if (_repo == null) return;
    _purchaseOrders = await _repo!.getPurchaseOrders();
    _supplierOrders = await _repo!.getAllSupplierOrders();
    notifyListeners();
  }

  /// Build a draft PurchaseOrder from current replenishment recommendations.
  PurchaseOrder buildOrderFromRecommendations(
      {List<ReplenishmentRecommendation>? selectedRecs}) {
    final recs = selectedRecs ??
        _recommendations
            .where((r) => r.status == 'Critical' || r.status == 'Order Now')
            .toList();

    final supplierMap = {for (final s in _suppliers) s.id: s};
    final productMap = {for (final p in _products) p.id: p};

    final items = recs.map((r) {
      final product = productMap[r.productId];
      final supplier =
          product?.supplierId != null ? supplierMap[product!.supplierId] : null;
      return PurchaseOrderItem(
        productId: r.productId,
        productName: r.productName,
        sku: r.sku,
        supplierId: supplier?.id,
        supplierName: supplier?.name,
        supplierEmail: supplier?.contactEmail,
        quantity: r.suggestedOrderQty,
        unitCost: product?.unitCost ?? 0,
      );
    }).toList();

    return PurchaseOrder(
      id: '',
      status: OrderStatus.draft,
      createdAt: DateTime.now(),
      createdByUid: _currentUser?.uid ?? '',
      createdByName: _currentUser?.name ?? '',
      items: items,
    );
  }

  /// Save a purchase order as draft (not yet confirmed).
  Future<PurchaseOrder?> saveDraftOrder(PurchaseOrder order) async {
    if (_repo == null) return null;
    try {
      order.status = OrderStatus.draft;
      final saved = await _repo!.addPurchaseOrder(order);
      _purchaseOrders.insert(0, saved);
      notifyListeners();
      return saved;
    } catch (e) {
      _errorMessage = 'Failed to save draft: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Confirm and save a purchase order; creates supplier orders automatically.
  Future<PurchaseOrder?> confirmPurchaseOrder(PurchaseOrder order) async {
    if (_repo == null) return null;

    try {
      order.status = OrderStatus.confirmed;
      final saved = await _repo!.addPurchaseOrder(order);

      // Split into supplier orders grouped by supplier
      final bySupplier = saved.itemsBySupplier;
      for (final entry in bySupplier.entries) {
        final supplierId = entry.key;
        final items = entry.value;
        if (supplierId == null) continue; // skip items without a supplier

        final token = _generateAccessToken();
        final supplierOrder = SupplierOrder(
          id: '${saved.id}_$supplierId',
          purchaseOrderId: saved.id,
          ownerUid: _currentUser!.uid,
          supplierId: supplierId,
          supplierName: items.first.supplierName ?? 'Unknown',
          supplierEmail: items.first.supplierEmail ?? '',
          status: 'pending',
          createdAt: DateTime.now(),
          items: items
              .map((i) => SupplierOrderItem(
                    productId: i.productId,
                    productName: i.productName,
                    sku: i.sku,
                    quantity: i.quantity,
                    unitCost: i.unitCost,
                  ))
              .toList(),
          accessToken: token,
          expiresAt: DateTime.now().add(const Duration(days: 30)),
        );
        await _repo!.addSupplierOrder(supplierOrder);
        _supplierOrders.add(supplierOrder);
      }

      _purchaseOrders.insert(0, saved);
      notifyListeners();
      return saved;
    } catch (e) {
      _errorMessage = 'Failed to create order: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Mark a purchase order as sent and trigger supplier emails.
  Future<void> markOrderSent(String orderId) async {
    if (_repo == null) return;
    final idx = _purchaseOrders.indexWhere((o) => o.id == orderId);
    if (idx == -1) return;
    _purchaseOrders[idx].status = OrderStatus.sent;
    await _repo!.updatePurchaseOrder(_purchaseOrders[idx]);

    // Trigger supplier emails via Cloud Function
    if (_currentUser != null) {
      _callCloudFunction(
        CloudFunctionConfig.sendSupplierEmails,
        {
          'uid': _currentUser!.uid,
          'purchaseOrderId': orderId,
        },
      );
    }

    notifyListeners();
  }

  /// Get supplier orders for a specific purchase order.
  List<SupplierOrder> getSupplierOrdersFor(String purchaseOrderId) {
    return _supplierOrders
        .where((o) => o.purchaseOrderId == purchaseOrderId)
        .toList();
  }

  /// Mark a supplier order as received: update status, increment raw material
  /// stock for each line item, and auto-complete the parent purchase order if
  /// all supplier orders are done.
  ///
  /// [receivedQuantities] is an optional map of `productId → actualReceived`.
  /// When provided, stock is incremented by the actual quantity; otherwise the
  /// full ordered quantity is used.
  Future<void> receiveSupplierOrder(
    String supplierOrderId, {
    Map<String, int>? receivedQuantities,
  }) async {
    if (_repo == null || _currentUser == null) return;

    final soIdx = _supplierOrders.indexWhere((o) => o.id == supplierOrderId);
    if (soIdx == -1) return;
    final so = _supplierOrders[soIdx];

    // 1. Mark supplier order as delivered
    so.status = 'delivered';
    await _repo!.updateSupplierOrder(so);

    // 2. Update product stock for each line item
    for (final item in so.items) {
      final pIdx = _products.indexWhere((p) => p.id == item.productId);
      if (pIdx != -1) {
        final qty = receivedQuantities?[item.productId] ?? item.quantity;
        _products[pIdx].currentStock += qty;
        await _repo!.updateProduct(_products[pIdx]);
      }
    }

    // 3. Log the receipt
    final logId = '${supplierOrderId}_received_${DateTime.now().millisecondsSinceEpoch}';
    final qtyDesc = receivedQuantities != null
        ? so.items
            .map((i) =>
                '${i.productName}: +${receivedQuantities[i.productId] ?? i.quantity}')
            .join(', ')
        : so.items.map((i) => '${i.productName}: +${i.quantity}').join(', ');
    await _repo!.addWorkflowLog(WorkflowLog(
      id: logId,
      entityType: 'supplierOrder',
      entityId: supplierOrderId,
      action: 'received',
      performedBy: _currentUser!.uid,
      timestamp: DateTime.now(),
      details: 'GRN — received from ${so.supplierName}. $qtyDesc.',
    ));

    // 4. Check if all supplier orders for this purchase order are delivered
    final purchaseOrderId = so.purchaseOrderId;
    final siblings = _supplierOrders
        .where((o) => o.purchaseOrderId == purchaseOrderId)
        .toList();
    final allDelivered = siblings.every((o) => o.status == 'delivered');

    if (allDelivered) {
      final poIdx = _purchaseOrders.indexWhere((o) => o.id == purchaseOrderId);
      if (poIdx != -1) {
        _purchaseOrders[poIdx].status = OrderStatus.completed;
        await _repo!.updatePurchaseOrder(_purchaseOrders[poIdx]);
      }
    } else {
      final poIdx = _purchaseOrders.indexWhere((o) => o.id == purchaseOrderId);
      if (poIdx != -1 && _purchaseOrders[poIdx].status != OrderStatus.partiallyFulfilled) {
        _purchaseOrders[poIdx].status = OrderStatus.partiallyFulfilled;
        await _repo!.updatePurchaseOrder(_purchaseOrders[poIdx]);
      }
    }

    // 5. Clear approvals for received products so that if stock is still below
    //    ROP after a partial delivery, the recommendation surfaces again.
    final receivedProductIds = so.items.map((i) => i.productId).toSet();
    _approvedRecommendations.removeAll(receivedProductIds);
    final batch2 = FirebaseFirestore.instance.batch();
    for (final pid in receivedProductIds) {
      batch2.delete(FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('approvals')
          .doc(pid));
    }
    await batch2.commit();

    _rebuildRecommendations();
    notifyListeners();
  }

  String _generateAccessToken() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(32, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ── Supply-Chain Data Loading ──────────────────────────────────────────────

  Future<void> loadManufacturingData() async {
    if (_repo == null) return;
    try {
      final results = await Future.wait([
        _repo!.getRawMaterials(),
        _repo!.getBOMs(),
        _repo!.getManufacturers(),
        _repo!.getProductionOrders(),
        _repo!.getRawMaterialOrders(),
        _repo!.getManufacturingRecommendations(),
        _repo!.getCashFlowSnapshots(),
      ]);
      _rawMaterials = results[0] as List<RawMaterial>;
      _boms = results[1] as List<BillOfMaterials>;
      _manufacturers = results[2] as List<Manufacturer>;
      _productionOrders = results[3] as List<ProductionOrder>;
      _rawMaterialOrders = results[4] as List<RawMaterialOrder>;
      _mfgRecommendations = results[5] as List<ManufacturingRecommendation>;
      _cashFlowSnapshots = results[6] as List<CashFlowSnapshot>;
      computeMinimumStockLevels();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load manufacturing data: $e';
      notifyListeners();
    }
  }

  // ── Raw Material CRUD ──────────────────────────────────────────────────────

  Future<void> addRawMaterial(RawMaterial material) async {
    final saved = await _repo!.addRawMaterial(material);
    _rawMaterials.add(saved);
    notifyListeners();
  }

  Future<void> updateRawMaterial(RawMaterial material) async {
    await _repo!.updateRawMaterial(material);
    final idx = _rawMaterials.indexWhere((m) => m.id == material.id);
    if (idx != -1) _rawMaterials[idx] = material;
    notifyListeners();
  }

  Future<void> deleteRawMaterial(String materialId) async {
    // Remove this RM from all BOM line items before deleting.
    for (var i = 0; i < _boms.length; i++) {
      final bom = _boms[i];
      if (bom.materials.any((m) => m.rawMaterialId == materialId)) {
        final updated = BillOfMaterials(
          id: bom.id,
          finalProductId: bom.finalProductId,
          materials: bom.materials.where((m) => m.rawMaterialId != materialId).toList(),
          isActive: bom.isActive,
        );
        await _repo!.updateBOM(updated);
        _boms[i] = updated;
      }
    }
    await _repo!.deleteRawMaterial(materialId);
    _rawMaterials.removeWhere((m) => m.id == materialId);
    notifyListeners();
  }

  // ── BOM CRUD ───────────────────────────────────────────────────────────────

  Future<void> addBOM(BillOfMaterials bom) async {
    final saved = await _repo!.addBOM(bom);
    _boms.add(saved);
    notifyListeners();
  }

  Future<void> updateBOM(BillOfMaterials bom) async {
    await _repo!.updateBOM(bom);
    final idx = _boms.indexWhere((b) => b.id == bom.id);
    if (idx != -1) _boms[idx] = bom;
    notifyListeners();
  }

  Future<void> deleteBOM(String bomId) async {
    await _repo!.deleteBOM(bomId);
    _boms.removeWhere((b) => b.id == bomId);
    notifyListeners();
  }

  // ── Manufacturer CRUD ──────────────────────────────────────────────────────

  Future<void> addManufacturer(Manufacturer manufacturer) async {
    final saved = await _repo!.addManufacturer(manufacturer);
    _manufacturers.add(saved);
    notifyListeners();
  }

  Future<void> updateManufacturer(Manufacturer manufacturer) async {
    await _repo!.updateManufacturer(manufacturer);
    final idx = _manufacturers.indexWhere((m) => m.id == manufacturer.id);
    if (idx != -1) _manufacturers[idx] = manufacturer;
    notifyListeners();
  }

  Future<void> deleteManufacturer(String manufacturerId) async {
    await _repo!.deleteManufacturer(manufacturerId);
    _manufacturers.removeWhere((m) => m.id == manufacturerId);
    notifyListeners();
  }

  // ── Manufacturing Recommendations ──────────────────────────────────────────

  Future<void> generateMfgRecommendations() async {
    // Try backend first; fall back to local computation
    try {
      final result = await _backendApi.generateRecommendations();
      _mfgRecommendations = result
          .map((json) => ManufacturingRecommendation.fromFirestore(
              json['id'] as String? ?? '', json as Map<String, dynamic>))
          .toList();
      notifyListeners();
      return;
    } catch (_) {
      // Backend unavailable — use local engine
    }

    final recs = _recEngine.generate(
      products: _products,
      boms: _boms,
      rawMaterials: _rawMaterials,
      demandByProduct: _demandByProduct,
      latestCashFlow: latestCashFlow,
    );
    _mfgRecommendations = recs;
    if (_repo != null) {
      await _repo!.saveManufacturingRecommendations(recs);
    }
    notifyListeners();
  }

  /// Approve a manufacturing recommendation → create a production order.
  Future<ProductionOrder?> approveMfgRecommendation(
    ManufacturingRecommendation rec,
    String manufacturerId,
  ) async {
    if (_currentUser == null || _manufacturingService == null || _workflowService == null) {
      return null;
    }

    _lastApprovalEmailsSent = 0;

    // Step A: Mark recommendation approved.
    rec.status = RecommendationStatus.approved;
    await _repo!.updateManufacturingRecommendation(rec);

    // Step B: Create ProductionOrder.
    final order = await _manufacturingService!.createProductionOrder(
      finalProductId: rec.productId,
      quantity: rec.suggestedQty,
      manufacturerId: manufacturerId,
      estimatedCost: rec.estimatedCost,
    );
    _productionOrders.insert(0, order);

    await _repo!.addWorkflowLog(WorkflowLog(
      id: 'wl_${order.id}_approved_${DateTime.now().millisecondsSinceEpoch}',
      entityType: 'ProductionOrder',
      entityId: order.id,
      action: 'approved',
      performedBy: _currentUser!.uid,
      timestamp: DateTime.now(),
      details: 'Production order created and approved for recommendation ${rec.id}',
    ));

    // Step C: Load BOM — throw BomMissingException so UI can show a
    // specific, actionable error message.
    final bom = _boms.where((b) => b.finalProductId == rec.productId).firstOrNull;
    if (bom == null) throw BomMissingException(rec.productId);

    // Step D: Persist RawMaterialOrders.
    final rmOrders = await _manufacturingService!.generateRawMaterialOrders(
      productionOrder: order,
      bom: bom,
      rawMaterials: _rawMaterials,
    );
    _rawMaterialOrders.addAll(rmOrders);

    await _repo!.addWorkflowLog(WorkflowLog(
      id: 'wl_${order.id}_rmo_${DateTime.now().millisecondsSinceEpoch}',
      entityType: 'ProductionOrder',
      entityId: order.id,
      action: 'raw_material_orders_created',
      performedBy: _currentUser!.uid,
      timestamp: DateTime.now(),
      details: '${rmOrders.length} raw material order(s) generated from BOM',
    ));

    // Step E: Create one factoryOrder doc per supplier (grouped).
    final supplierCount = await _createPerSupplierFactoryOrders(order, rmOrders);

    // Step F: Send supplier emails — only if factory orders were created,
    // otherwise the CF would return 404 and surface an unhelpful error.
    int emailsSent = 0;
    if (supplierCount == 0) {
      // No suppliers linked to any raw material — skip factory emails.
      await _repo!.addWorkflowLog(WorkflowLog(
        id: 'wl_${order.id}_no_suppliers_${DateTime.now().millisecondsSinceEpoch}',
        entityType: 'ProductionOrder',
        entityId: order.id,
        action: 'supplier_emails_skipped',
        performedBy: _currentUser!.uid,
        timestamp: DateTime.now(),
        details: 'No suppliers linked to raw materials — factory emails skipped',
      ));
    } else {
    try {
      final result = await _invokeCloudFunction(
        CloudFunctionConfig.sendFactoryEmails,
        {'uid': _currentUser!.uid, 'productionOrderId': order.id},
      );
      final results = (result['results'] as List<dynamic>?) ?? [];
      emailsSent += results.where((r) => (r as Map)['status'] == 'sent').length;
      await _repo!.addWorkflowLog(WorkflowLog(
        id: 'wl_${order.id}_supplier_emails_${DateTime.now().millisecondsSinceEpoch}',
        entityType: 'ProductionOrder',
        entityId: order.id,
        action: 'supplier_emails_sent',
        performedBy: _currentUser!.uid,
        timestamp: DateTime.now(),
        details: '$emailsSent of $supplierCount supplier email(s) sent',
      ));
    } catch (e) {
      await _repo!.addWorkflowLog(WorkflowLog(
        id: 'wl_${order.id}_supplier_emails_failed_${DateTime.now().millisecondsSinceEpoch}',
        entityType: 'ProductionOrder',
        entityId: order.id,
        action: 'supplier_emails_failed',
        performedBy: _currentUser!.uid,
        timestamp: DateTime.now(),
        details: 'Supplier email dispatch failed: $e',
      ));
      rethrow;
    }
    } // end if (supplierCount > 0)

    // Step G: Transition PO → materialsOrdered.
    await _workflowService!.transitionProductionOrder(
      order,
      ProductionOrderStatus.materialsOrdered,
      _currentUser!.uid,
    );

    // Step H: Create manufacturer portal doc and send email (non-critical).
    await _createManufacturerPortalOrderAtApproval(order, rmOrders);
    try {
      final mfrResult = await _invokeCloudFunction(
        CloudFunctionConfig.sendManufacturerEmails,
        {'uid': _currentUser!.uid, 'productionOrderId': order.id},
      );
      final mfrResults = (mfrResult['results'] as List<dynamic>?) ?? [];
      emailsSent +=
          mfrResults.where((r) => (r as Map)['status'] == 'sent').length;
      await _repo!.addWorkflowLog(WorkflowLog(
        id: 'wl_${order.id}_mfr_email_${DateTime.now().millisecondsSinceEpoch}',
        entityType: 'ProductionOrder',
        entityId: order.id,
        action: 'manufacturer_email_sent',
        performedBy: _currentUser!.uid,
        timestamp: DateTime.now(),
        details: 'Manufacturer notification email sent',
      ));
    } catch (e) {
      // Non-critical: manufacturer email failure does not roll back the approval.
      await _repo!.addWorkflowLog(WorkflowLog(
        id: 'wl_${order.id}_mfr_email_failed_${DateTime.now().millisecondsSinceEpoch}',
        entityType: 'ProductionOrder',
        entityId: order.id,
        action: 'manufacturer_email_failed',
        performedBy: _currentUser!.uid,
        timestamp: DateTime.now(),
        details: 'Manufacturer email failed (non-critical): $e',
      ));
    }

    _lastApprovalEmailsSent = emailsSent;
    notifyListeners();
    return order;
  }

  /// Creates one [factoryOrder] Firestore doc per supplier, each containing
  /// an array of all raw materials they need to supply. Returns supplier count.
  Future<int> _createPerSupplierFactoryOrders(
    ProductionOrder order,
    List<RawMaterialOrder> rmOrders,
  ) async {
    final firestoreRepo = _firestoreRepo;
    if (firestoreRepo == null || _currentUser == null) return 0;

    // Group raw material orders by supplierId.
    final Map<String, List<RawMaterialOrder>> bySupplier = {};
    for (final rmo in rmOrders) {
      if (rmo.supplierId.isEmpty) continue;
      bySupplier.putIfAbsent(rmo.supplierId, () => []).add(rmo);
    }

    for (final entry in bySupplier.entries) {
      final supplierId = entry.key;
      final supplierRmos = entry.value;
      final supplier =
          _suppliers.where((s) => s.id == supplierId).firstOrNull;

      final materials = supplierRmos.map((rmo) {
        final rm =
            _rawMaterials.where((r) => r.id == rmo.rawMaterialId).firstOrNull;
        return {
          'rawMaterialOrderId': rmo.id,
          'rawMaterialId': rmo.rawMaterialId,
          'materialName': rm?.name ?? '',
          'quantity': rmo.quantity,
          'unit': rm?.unit ?? 'pcs',
          'requestedDate': Timestamp.fromDate(rmo.requestedDate),
        };
      }).toList();

      await firestoreRepo.addFactoryOrder({
        'productionOrderId': order.id,
        'supplierId': supplierId,
        'supplierName': supplier?.name ?? '',
        'supplierEmail': supplier?.contactEmail ?? '',
        'status': 'pending',
        'accessToken': _generateAccessToken(),
        'expiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 30))),
        'materials': materials,
      });
    }

    return bySupplier.length;
  }

  /// Creates the manufacturer portal order doc at approval time (not when
  /// materials arrive), including which suppliers are providing each material.
  Future<void> _createManufacturerPortalOrderAtApproval(
    ProductionOrder po,
    List<RawMaterialOrder> rmOrders,
  ) async {
    final firestoreRepo = _firestoreRepo;
    if (firestoreRepo == null || _currentUser == null) return;

    final product =
        _products.where((p) => p.id == po.finalProductId).firstOrNull;
    final mfr =
        _manufacturers.where((m) => m.id == po.manufacturerId).firstOrNull;

    final rmOrdersData = rmOrders.map((rmo) {
      final rm =
          _rawMaterials.where((r) => r.id == rmo.rawMaterialId).firstOrNull;
      final supplier =
          _suppliers.where((s) => s.id == rmo.supplierId).firstOrNull;
      return {
        'materialName': rm?.name ?? '',
        'quantity': rmo.quantity,
        'unit': rm?.unit ?? 'pcs',
        'status': rmo.status,
        'supplierName': supplier?.name ?? '',
      };
    }).toList();

    final incomingSuppliers = rmOrders
        .map((rmo) =>
            _suppliers.where((s) => s.id == rmo.supplierId).firstOrNull?.name)
        .whereType<String>()
        .toSet()
        .toList();

    await firestoreRepo.addManufacturerOrder({
      'productionOrderId': po.id,
      'productName': product?.name ?? '',
      'quantity': po.quantity,
      'estimatedCost': po.estimatedCost,
      'manufacturerId': po.manufacturerId,
      'manufacturerName': mfr?.name ?? '',
      'manufacturerEmail': mfr?.contactEmail ?? '',
      'status': 'pending',
      'accessToken': _generateAccessToken(),
      'rawMaterialOrders': rmOrdersData,
      'incomingSuppliers': incomingSuppliers,
      'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 30))),
    });
  }

  Future<void> rejectMfgRecommendation(ManufacturingRecommendation rec) async {
    rec.status = RecommendationStatus.rejected;
    await _repo!.updateManufacturingRecommendation(rec);
    notifyListeners();
  }

  /// Delete a draft production order.
  Future<void> deleteProductionOrder(String orderId) async {
    if (_repo == null) return;
    try {
      await _backendApi.deleteProductionOrder(orderId);
    } catch (_) {
      // Fallback: delete directly from Firestore
      await _repo!.deleteProductionOrder(orderId);
    }
    _productionOrders.removeWhere((o) => o.id == orderId);
    notifyListeners();
  }

  /// Cancel an active production order.
  Future<void> cancelProductionOrder(String orderId) async {
    if (_repo == null) return;
    final idx = _productionOrders.indexWhere((o) => o.id == orderId);
    if (idx == -1) return;
    // Delete it (backend endpoint) — production orders have no "cancelled" status
    try {
      await _backendApi.deleteProductionOrder(orderId);
    } catch (_) {
      await _repo!.deleteProductionOrder(orderId);
    }
    _productionOrders.removeAt(idx);
    notifyListeners();
  }

  // ── Production Order Status ────────────────────────────────────────────────

  /// Convert camelCase enum name to snake_case for backend API.
  static String _toSnake(String camel) =>
      camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

  Future<void> updateProductionOrderStatus(
    ProductionOrder order,
    ProductionOrderStatus newStatus,
  ) async {
    if (_currentUser == null) return;

    // Try backend first
    try {
      await _backendApi.updateProductionOrderStatus(
        order.id,
        _toSnake(newStatus.name),
      );
      order.status = newStatus;

      if (newStatus == ProductionOrderStatus.inProduction) {
        // Deduct raw materials consumed by manufacturing
        await _deductRawMaterialsForProduction(order);
        // Send email to manufacturer
        _sendManufacturerEmail(order);
      }

      if (newStatus == ProductionOrderStatus.completed) {
        order.completedAt = DateTime.now();
        final product = _products.where((p) => p.id == order.finalProductId).firstOrNull;
        if (product != null) {
          product.currentStock += order.quantity;
          await _repo?.updateProduct(product);
        }
        // Clear approval so that if stock falls below ROP again the
        // recommendation will surface in openRecommendations.
        _approvedRecommendations.remove(order.finalProductId);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('approvals')
            .doc(order.finalProductId)
            .delete();
        _rebuildRecommendations();
      }
      notifyListeners();
      return;
    } catch (_) {
      // Backend unavailable — fall back to local workflow
    }

    // Fallback: local workflow
    if (_workflowService == null) return;
    await _workflowService!.transitionProductionOrder(
      order,
      newStatus,
      _currentUser!.uid,
    );

    if (newStatus == ProductionOrderStatus.inProduction) {
      await _deductRawMaterialsForProduction(order);
      _sendManufacturerEmail(order);
    }

    if (newStatus == ProductionOrderStatus.completed) {
      order.completedAt = DateTime.now();
      final product = _products.where((p) => p.id == order.finalProductId).firstOrNull;
      if (product != null) {
        product.currentStock += order.quantity;
        await _repo!.updateProduct(product);
      }
      // Clear approval so that if stock falls below ROP again the
      // recommendation will surface in openRecommendations.
      _approvedRecommendations.remove(order.finalProductId);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('approvals')
          .doc(order.finalProductId)
          .delete();
      _rebuildRecommendations();
    }

    notifyListeners();
  }

  /// Deduct raw material stock when production starts.
  Future<void> _deductRawMaterialsForProduction(ProductionOrder order) async {
    final rmOrders = _rawMaterialOrders
        .where((o) => o.productionOrderId == order.id)
        .toList();

    for (final rmo in rmOrders) {
      final rmIdx = _rawMaterials.indexWhere((r) => r.id == rmo.rawMaterialId);
      if (rmIdx != -1) {
        _rawMaterials[rmIdx].currentStock -= rmo.quantity;
        if (_rawMaterials[rmIdx].currentStock < 0) {
          _rawMaterials[rmIdx].currentStock = 0;
        }
        await _repo?.updateRawMaterial(_rawMaterials[rmIdx]);
      }
    }

    // Log consumption
    if (_repo != null && _currentUser != null) {
      final materialNames = rmOrders.map((rmo) {
        final rm = _rawMaterials.where((r) => r.id == rmo.rawMaterialId).firstOrNull;
        return '${rm?.name ?? rmo.rawMaterialId}: ${rmo.quantity} ${rm?.unit ?? "units"}';
      }).join(', ');

      await _repo!.addWorkflowLog(WorkflowLog(
        id: '${order.id}_materials_consumed_${DateTime.now().millisecondsSinceEpoch}',
        entityType: 'ProductionOrder',
        entityId: order.id,
        action: 'raw_materials_consumed',
        performedBy: _currentUser!.uid,
        timestamp: DateTime.now(),
        details: 'Raw materials consumed for production: $materialNames',
      ));
    }
  }

  /// Send email notification to manufacturer when production starts.
  void _sendManufacturerEmail(ProductionOrder order) {
    if (_currentUser == null) return;
    _callCloudFunction(
      CloudFunctionConfig.sendManufacturerEmails,
      {
        'uid': _currentUser!.uid,
        'productionOrderId': order.id,
        'manufacturerId': order.manufacturerId,
      },
    );
  }

  // ── Raw Material Order Status ──────────────────────────────────────────────

  Future<void> updateRawMaterialOrderStatus(
    RawMaterialOrder order,
    String newStatus,
  ) async {
    if (_currentUser == null) return;

    // Try backend first
    try {
      await _backendApi.updateRawMaterialOrderStatus(order.id, newStatus);
      order.status = newStatus;

      // Backend auto-transitions PO when all materials complete
      if (newStatus == 'completed') {
        _productionOrders = await _repo!.getProductionOrders();
        final po = _productionOrders
            .where((o) => o.id == order.productionOrderId)
            .firstOrNull;
        if (po != null && po.status == ProductionOrderStatus.materialsReady) {
          await _createManufacturerPortalOrder(po);
        }
      }

      notifyListeners();
      return;
    } catch (_) {
      // Backend unavailable — fall back to local workflow
    }

    // Fallback: local workflow
    if (_workflowService == null) return;
    await _workflowService!.updateRawMaterialOrderStatus(
      order,
      newStatus,
      _currentUser!.uid,
    );

    if (newStatus == 'completed') {
      final allReady =
          await _workflowService!.areAllMaterialsReady(order.productionOrderId);
      if (allReady) {
        final po = _productionOrders
            .where((o) => o.id == order.productionOrderId)
            .firstOrNull;
        if (po != null && po.status == ProductionOrderStatus.materialsOrdered) {
          await _workflowService!.transitionProductionOrder(
            po,
            ProductionOrderStatus.materialsReady,
            'system',
          );
          await _createManufacturerPortalOrder(po);
        }
      }
    }

    notifyListeners();
  }

  /// Creates a top-level manufacturer portal order and triggers notification emails.
  Future<void> _createManufacturerPortalOrder(ProductionOrder po) async {
    final firestoreRepo = _firestoreRepo;
    if (firestoreRepo == null || _currentUser == null) return;

    final rng = Random.secure();
    final token = List.generate(
      32,
      (_) => 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'[
          rng.nextInt(62)],
    ).join();

    final product = _products
        .where((p) => p.id == po.finalProductId)
        .firstOrNull;
    final mfr = _manufacturers
        .where((m) => m.id == po.manufacturerId)
        .firstOrNull;

    final siblingRmos = _rawMaterialOrders
        .where((o) => o.productionOrderId == po.id)
        .toList();
    final rmOrdersData = siblingRmos.map((rmo) {
      final rm = _rawMaterials
          .where((r) => r.id == rmo.rawMaterialId)
          .firstOrNull;
      return {
        'materialName': rm?.name ?? '',
        'quantity': rmo.quantity,
        'status': rmo.status,
      };
    }).toList();

    await firestoreRepo.addManufacturerOrder({
      'productionOrderId': po.id,
      'productName': product?.name ?? '',
      'quantity': po.quantity,
      'estimatedCost': po.estimatedCost,
      'manufacturerId': po.manufacturerId,
      'manufacturerName': mfr?.name ?? '',
      'manufacturerEmail': mfr?.contactEmail ?? '',
      'status': 'pending',
      'accessToken': token,
      'rawMaterialOrders': rmOrdersData,
      'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 30))),
    });

    _callCloudFunction(
      CloudFunctionConfig.sendManufacturerEmails,
      {'uid': _currentUser!.uid, 'productionOrderId': po.id},
    );
  }

  // ── Cash Flow ──────────────────────────────────────────────────────────────

  Future<CashFlowSnapshot?> importCashFlowFromRows(
    List<Map<String, dynamic>> rows,
  ) async {
    if (_cashFlowService == null) return null;
    final snapshot = await _cashFlowService!.importFromRows(rows);
    _cashFlowSnapshots.insert(0, snapshot);

    // Also upload to backend for workflow logging
    try {
      await _backendApi.uploadCashFlowSnapshot(snapshot.toFirestore());
    } catch (_) {
      // Backend unavailable — local save already handled by service
    }

    notifyListeners();
    return snapshot;
  }

  Future<CashFlowSnapshot?> importCashFlowFromExcel(Uint8List bytes) async {
    if (_cashFlowService == null) return null;
    final snapshot = await _cashFlowService!.importFromExcelBytes(bytes);
    _cashFlowSnapshots.insert(0, snapshot);

    // Also upload to backend for workflow logging
    try {
      await _backendApi.uploadCashFlowSnapshot(snapshot.toFirestore());
    } catch (_) {
      // Backend unavailable — local save already handled by service
    }

    notifyListeners();
    return snapshot;
  }

  // ── Workflow Logs ──────────────────────────────────────────────────────────

  Future<void> loadWorkflowLogs({String? entityType, String? entityId}) async {
    if (_repo == null) return;
    _workflowLogs = await _repo!.getWorkflowLogs(
      entityType: entityType,
      entityId: entityId,
    );
    notifyListeners();
  }

  // ── Raw Material Purchase Orders ───────────────────────────────────────────

  /// BOM-explodes a forecast qty into draft RawMaterialPurchaseOrders (one per supplier).
  Future<List<RawMaterialPurchaseOrder>> createRawMaterialOrders(
    String productId,
    double forecastQty,
  ) async {
    final orders = _rmOrderService.createFromForecast(
      productId: productId,
      forecastQty: forecastQty,
      boms: _boms,
      rawMaterials: _rawMaterials,
      suppliers: _suppliers,
      forecastProductId: productId,
    );
    return orders;
  }

  Future<void> saveRawMaterialPurchaseOrders(
    List<RawMaterialPurchaseOrder> orders,
  ) async {
    if (_repo == null || _currentUser == null) return;
    for (final order in orders) {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('rawMaterialPurchaseOrders')
          .doc(order.id);
      await ref.set(order.toFirestore());
      _rmPurchaseOrders.add(order);
    }
    notifyListeners();
  }

  Future<void> confirmRawMaterialPurchaseOrder(String orderId) async {
    if (_currentUser == null) return;
    final idx = _rmPurchaseOrders.indexWhere((o) => o.id == orderId);
    if (idx == -1) return;
    _rmPurchaseOrders[idx].status = 'sent';
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('rawMaterialPurchaseOrders')
        .doc(orderId);
    await ref.update({'status': 'sent'});
    notifyListeners();
  }

  /// Invokes the `sendRawMaterialSupplierEmail` Cloud Function for a single
  /// RM purchase order. Returns true on success, false on any failure (caller
  /// can use the return value to report per-supplier delivery in the UI).
  /// Non-blocking — order status is the source of truth; email is notification.
  Future<bool> sendRawMaterialOrderEmail(String orderId) async {
    if (_currentUser == null) return false;
    try {
      await _invokeCloudFunction(
        CloudFunctionConfig.sendRawMaterialSupplierEmail,
        {
          'uid': _currentUser!.uid,
          'rawMaterialPurchaseOrderId': orderId,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── BOM Active State ───────────────────────────────────────────────────────

  /// Sets the given BOM as active for its product; deactivates all others
  /// for the same product.
  Future<void> setActiveBOM(String bomId, String productId) async {
    if (_repo == null) return;
    for (var i = 0; i < _boms.length; i++) {
      if (_boms[i].finalProductId != productId) continue;
      final shouldBeActive = _boms[i].id == bomId;
      if (_boms[i].isActive == shouldBeActive) continue;
      final updated = BillOfMaterials(
        id: _boms[i].id,
        finalProductId: _boms[i].finalProductId,
        materials: _boms[i].materials,
        isActive: shouldBeActive,
      );
      await _repo!.updateBOM(updated);
      _boms[i] = updated;
    }
    computeMinimumStockLevels();
    notifyListeners();
  }

  // ── Onboarding ─────────────────────────────────────────────────────────────

  Future<void> completeOnboardingStep(String step) async {
    if (_currentUser == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('settings')
        .doc('onboarding');
    await ref.set({'completedSteps': FieldValue.arrayUnion([step])}, SetOptions(merge: true));
    if (step == 'done') {
      _onboardingComplete = true;
      notifyListeners();
      // Trigger router redirect re-evaluation so the wizard guard releases.
      authNotifier.notifyAuthChanged();
    }
  }

  Future<void> loadOnboardingState() async {
    if (_currentUser == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('settings')
        .doc('onboarding');
    final snap = await ref.get();
    if (snap.exists) {
      final steps = List<String>.from(snap.data()?['completedSteps'] ?? []);
      _onboardingComplete = steps.contains('done');
    }
    _onboardingStateLoaded = true;
    notifyListeners();
    // Notify router so the onboarding redirect runs against the loaded state.
    authNotifier.notifyAuthChanged();
  }

  // ── Cloud Function Helpers ─────────────────────────────────────────────────

  /// Fire-and-forget call to a Cloud Function endpoint. Errors are silently
  /// ignored — use [_invokeCloudFunction] when you need to surface errors.
  void _callCloudFunction(String url, Map<String, dynamic> body) {
    _invokeCloudFunction(url, body).catchError((_) => <String, dynamic>{});
  }

  /// Awaitable Cloud Function call that throws [CloudFunctionException] on
  /// non-2xx responses. Returns the decoded JSON body on success.
  Future<Map<String, dynamic>> _invokeCloudFunction(
    String url,
    Map<String, dynamic> body,
  ) async {
    final user = _authService.currentUser;
    final token = await user?.getIdToken();
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudFunctionException(
        response.statusCode,
        (decoded['error'] as String?) ??
            'Cloud Function returned ${response.statusCode}',
      );
    }
    return decoded;
  }
}
