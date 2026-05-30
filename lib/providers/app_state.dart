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
  StreamSubscription<Map<String, List<DomainDemandRecord>>>? _demandSub;
  Timer? _shopifyAutoSyncTimer;
  // Shopify auto-sync status (surfaced to UI so users can see whether the
  // background sync is actually working).
  DateTime? _lastShopifySyncAt;
  Map<String, dynamic>? _lastShopifySyncResult;
  String? _lastShopifySyncError;
  bool _shopifySyncInProgress = false;
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
    _demandSub?.cancel();
    _shopifyAutoSyncTimer?.cancel();
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
    _demandSub?.cancel();
    _demandSub = null;
    _shopifyAutoSyncTimer?.cancel();
    _shopifyAutoSyncTimer = null;
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
  /// Only active products. Archived/inactive items (e.g. products archived in
  /// Shopify) are hidden from the UI everywhere by default. Use [allProducts]
  /// for the rare case where you need the full list (settings/admin).
  List<Product> get products =>
      _products.where((p) => p.isActive).toList(growable: false);

  /// Unfiltered product list including inactive/archived items.
  List<Product> get allProducts => _products;
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
  DateTime? get lastShopifySyncAt => _lastShopifySyncAt;
  Map<String, dynamic>? get lastShopifySyncResult => _lastShopifySyncResult;
  String? get lastShopifySyncError => _lastShopifySyncError;
  bool get shopifySyncInProgress => _shopifySyncInProgress;

  /// Public manual trigger for an immediate Shopify sales sync. Returns the
  /// result map from the Cloud Function (or null on error/disconnected).
  Future<Map<String, dynamic>?> syncShopifyNow() async {
    await _silentShopifySync();
    return _lastShopifySyncResult;
  }
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

  Future<Product> addProduct(Product product) async {
    try {
      final saved = await _repo!.addProduct(product);
      _products.add(saved);
      _rebuildRecommendations();
      notifyListeners();
      return saved;
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

  /// Assigns a supplier to many products at once — used after a Shopify
  /// import to wire freshly-imported (purchased) products to the supplier
  /// they're bought from so the reorder/bulk-order engine can group them.
  /// Returns the number of products updated.
  Future<int> assignSupplierToProducts(
      List<String> productIds, String supplierId) async {
    if (supplierId.isEmpty || productIds.isEmpty) return 0;
    int updated = 0;
    for (final id in productIds) {
      final idx = _products.indexWhere((p) => p.id == id);
      if (idx == -1) continue;
      final next = _products[idx].copyWith(supplierId: supplierId);
      await _repo!.updateProduct(next);
      _products[idx] = next;
      updated++;
    }
    if (updated > 0) {
      _rebuildRecommendations();
      notifyListeners();
    }
    return updated;
  }

  /// Marks many products as MANUFACTURED by attaching a manufacturer. Their
  /// unit cost then comes from their Bill of Materials (raw materials +
  /// production fee) instead of a single supplier price, and they're routed
  /// to the BOM step rather than the supplier-link step. Returns the number
  /// of products updated.
  Future<int> assignManufacturerToProducts(
      List<String> productIds, String manufacturerId) async {
    if (manufacturerId.isEmpty || productIds.isEmpty) return 0;
    int updated = 0;
    for (final id in productIds) {
      final idx = _products.indexWhere((p) => p.id == id);
      if (idx == -1) continue;
      final next = _products[idx].copyWith(manufacturerId: manufacturerId);
      await _repo!.updateProduct(next);
      _products[idx] = next;
      updated++;
    }
    if (updated > 0) {
      _rebuildRecommendations();
      notifyListeners();
    }
    return updated;
  }

  /// Update the on-hand count for a specific warehouse location. Recomputes
  /// [Product.currentStock] as the sum of all warehouse quantities so the
  /// rest of the codebase (replenishment, forecasts) sees the updated total
  /// without requiring a migration.
  Future<void> setStockAtWarehouse(
    String productId,
    String warehouseId,
    int qty,
  ) async {
    final idx = _products.indexWhere((p) => p.id == productId);
    if (idx == -1) return;
    final p = _products[idx];
    final updated = Map<String, int>.from(p.stockByWarehouse);
    if (qty <= 0) {
      updated.remove(warehouseId);
    } else {
      updated[warehouseId] = qty;
    }
    final totalStock = updated.isEmpty
        ? p.currentStock
        : updated.values.fold(0, (a, b) => a + b);
    final newProduct = Product(
      id: p.id,
      sku: p.sku,
      name: p.name,
      category: p.category,
      unitCost: p.unitCost,
      currentStock: totalStock,
      supplierId: p.supplierId,
      manufacturerId: p.manufacturerId,
      warehouseId: p.warehouseId,
      isActive: p.isActive,
      leadTimeDays: p.leadTimeDays,
      averageDailySales: p.averageDailySales,
      minimumStock: p.minimumStock,
      shopifyVariantId: p.shopifyVariantId,
      shopifyProductId: p.shopifyProductId,
      imageUrl: p.imageUrl,
      sellingPrice: p.sellingPrice,
      productionFee: p.productionFee,
      shopifyUnitCost: p.shopifyUnitCost,
      isBundle: p.isBundle,
      bundleComponents: p.bundleComponents,
      sourcingOptions: p.sourcingOptions,
      stockByWarehouse: updated,
    );
    await updateProduct(newProduct);
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
        final updated = p.copyWith(warehouseId: warehouseId);
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

  /// Active products not yet assigned to a physical warehouse. Their on-hand
  /// stock isn't located anywhere, so they don't show up in per-warehouse
  /// KPIs. Surfacing these lets the user wire imported products to a location.
  List<Product> get productsMissingWarehouse => _products
      .where((p) =>
          p.isActive &&
          (p.warehouseId == null || p.warehouseId!.isEmpty) &&
          p.stockByWarehouse.isEmpty)
      .toList(growable: false);

  /// Bulk-assigns a warehouse to many products (typically right after a
  /// Shopify import). For products that have no per-warehouse stock breakdown
  /// yet, their entire current on-hand count is placed at the chosen
  /// warehouse so the warehouse's stored-units / SKU KPIs populate.
  /// Returns the number of products updated.
  Future<int> assignWarehouseToProducts(
      List<String> productIds, String warehouseId) async {
    if (warehouseId.isEmpty || productIds.isEmpty) return 0;
    int updated = 0;
    for (final id in productIds) {
      final idx = _products.indexWhere((p) => p.id == id);
      if (idx == -1) continue;
      final p = _products[idx];
      final byWh = Map<String, int>.from(p.stockByWarehouse);
      // Allocate existing on-hand stock to this warehouse if nothing has been
      // located yet — keeps currentStock and the per-warehouse map consistent.
      if (byWh.isEmpty && p.currentStock > 0) {
        byWh[warehouseId] = p.currentStock;
      }
      final next = p.copyWith(warehouseId: warehouseId, stockByWarehouse: byWh);
      await _repo!.updateProduct(next);
      _products[idx] = next;
      updated++;
    }
    if (updated > 0) {
      _rebuildRecommendations();
      notifyListeners();
    }
    return updated;
  }

  /// Total on-hand units physically located at [warehouseId]. Prefers the
  /// per-warehouse [Product.stockByWarehouse] breakdown; falls back to the
  /// legacy single-location model (`warehouseId` + `currentStock`).
  int unitsStoredAt(String warehouseId) {
    int total = 0;
    for (final p in _products) {
      if (!p.isActive) continue;
      if (p.stockByWarehouse.isNotEmpty) {
        total += p.stockByWarehouse[warehouseId] ?? 0;
      } else if (p.warehouseId == warehouseId) {
        total += p.currentStock;
      }
    }
    return total;
  }

  /// Number of distinct active SKUs stored at [warehouseId].
  int skuCountAt(String warehouseId) {
    int count = 0;
    for (final p in _products) {
      if (!p.isActive) continue;
      if (p.stockByWarehouse.isNotEmpty) {
        if ((p.stockByWarehouse[warehouseId] ?? 0) > 0) count++;
      } else if (p.warehouseId == warehouseId) {
        count++;
      }
    }
    return count;
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

  Future<Supplier> addSupplier(Supplier supplier) async {
    try {
      final saved = await _repo!.addSupplier(supplier);
      _suppliers.add(saved);
      notifyListeners();
      return saved;
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
    // The router's redirect callback checks `settings.businessProfile`.
    // Kicking authNotifier here makes the router re-evaluate after the
    // initial login load so the wizard redirect fires (or doesn't) with
    // accurate data instead of the default empty settings.
    authNotifier.notifyAuthChanged();
  }

  Future<void> saveSettings(UserSettings updated) async {
    if (_settingsService == null) return;
    await _settingsService!.save(updated);
    _settings = updated;
    notifyListeners();
    authNotifier.notifyAuthChanged();
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
      supplierId: supplierId,
    );

    // Create PO + SupplierOrders.
    final po = await confirmPurchaseOrder(draft);

    if (po != null && (supplier?.contactEmail.isNotEmpty ?? false)) {
      // Mark as sent and send supplier emails. A mail/SMTP failure must not
      // abort the approval — the PO + SupplierOrders are already persisted, so
      // we swallow the error and simply report that no email went out.
      try {
        await _invokeCloudFunction(
          CloudFunctionConfig.sendSupplierEmails,
          {'uid': _currentUser!.uid, 'purchaseOrderId': po.id},
        );
        _lastApprovalEmailsSent = 1;
      } catch (_) {
        _lastApprovalEmailsSent = 0;
      }
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
      } catch (e) {
        debugPrint('[approveReplenishmentManufacture] factory email failed: $e');
      }
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
    } catch (e) {
      debugPrint('[approveReplenishmentManufacture] manufacturer email failed: $e');
    }

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

  /// Saves a replenishment recommendation as a *draft* PurchaseOrder.
  /// No emails are sent and no approval record is created. The PO appears on
  /// /orders and can be confirmed + sent from the order detail screen.
  Future<PurchaseOrder?> saveDraftPOFromRecommendation(
      ReplenishmentRecommendation rec) async {
    if (_repo == null || _currentUser == null) return null;

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

    final poNum = await _nextPoNumber();
    final draft = PurchaseOrder(
      id: '',
      status: OrderStatus.draft,
      createdAt: DateTime.now(),
      createdByUid: _currentUser!.uid,
      createdByName: _currentUser!.name,
      items: [item],
      poNumber: poNum,
      supplierId: supplierId,
    );

    final saved = await _repo!.addPurchaseOrder(draft);
    _purchaseOrders.insert(0, saved);
    notifyListeners();
    return saved;
  }

  /// Saves a manufacturing replenishment recommendation as a *draft*
  /// ProductionOrder. No RM orders are created and no emails are sent.
  Future<ProductionOrder?> saveDraftProductionOrderFromRecommendation(
      ReplenishmentRecommendation rec) async {
    if (_repo == null ||
        _currentUser == null ||
        _manufacturingService == null) {
      return null;
    }

    final product = _products.where((p) => p.id == rec.productId).firstOrNull;
    final manufacturerId = product?.manufacturerId ?? '';
    if (manufacturerId.isEmpty) return null;

    final bom =
        _boms.where((b) => b.finalProductId == rec.productId).firstOrNull;
    final estimatedCost = bom == null
        ? 0.0
        : bom.materials.fold<double>(0.0, (acc, mat) {
            final rm = _rawMaterials
                .where((r) => r.id == mat.rawMaterialId)
                .firstOrNull;
            return acc +
                (rm?.unitCost ?? 0) * mat.quantityPerUnit * rec.suggestedOrderQty;
          });

    final order = await _manufacturingService!.createProductionOrder(
      finalProductId: rec.productId,
      quantity: rec.suggestedOrderQty,
      manufacturerId: manufacturerId,
      estimatedCost: estimatedCost,
    );
    _productionOrders.insert(0, order);
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

  /// Effective unit cost for a product. For bundles, this is the sum of
  /// `component.unitCost × quantity` over each bundle component (resolved by
  /// Shopify variant id). For non-bundle products, it's simply [Product.unitCost].
  ///
  /// Use this everywhere stock value / COGS is calculated so bundle pricing
  /// stays consistent with Shopify (where the bundle inherits the cost of
  /// its components).
  /// Effective unit cost for a product — the **single source of truth** for
  /// any cost-basis KPI. The cost comes from ONE of these sources, in order:
  ///
  ///   1. **Bundle** (composed of other variants): Σ over `bundleComponents`
  ///      of `(componentEffectiveCost × quantity)`. Components are resolved
  ///      via `productId` or `shopifyVariantId`.
  ///   2. **Manufactured product** (has `manufacturerId`): Σ over the linked
  ///      BOM of `(rawMaterial.unitCost × quantityPerUnit)` PLUS the
  ///      product's `productionFee` (per-unit fee charged by the manufacturer
  ///      on top of materials).
  ///   3. **Purchased product** (default): the user-entered `unitCost` —
  ///      what the supplier charges per unit.
  ///
  /// Costs are NEVER pulled from Shopify (Shopify's "Cost per item" is
  /// ignored). Selling price still comes from Shopify, but cost is always
  /// derived from raw-materials + manufacturing fees, or from the supplier
  /// price typed in by the user. This guarantees the inventory cost shown
  /// on the dashboard matches what the business actually pays.
  double effectiveUnitCost(Product p) =>
      _unitCostCache.putIfAbsent(p.id, () => _effectiveUnitCost(p, <String>{}));

  /// Per-frame memo for [effectiveUnitCost]. The cost is a pure function of the
  /// current product/BOM/raw-material state, and that state only changes
  /// alongside a [notifyListeners] call — so clearing the cache there keeps it
  /// always-fresh while collapsing the 50+ recursive recomputations a single
  /// table rebuild used to trigger into one lookup per product.
  final Map<String, double> _unitCostCache = {};

  @override
  void notifyListeners() {
    _unitCostCache.clear();
    super.notifyListeners();
  }


  /// Depth-tracked recursive cost calculator.
  ///
  /// [visiting] is the set of product ids currently on the call stack — when
  /// a sub-assembly references a product that's already being computed
  /// (direct or transitive loop) we bail out at 0 for that branch instead
  /// of recursing forever. Also caps total recursion depth at 5 to match the
  /// product-level decision in the plan: nobody should need to nest BOMs
  /// more than five levels deep, and runaway data shouldn't lock the UI.
  static const int _kMaxBomDepth = 5;

  double _effectiveUnitCost(Product p, Set<String> visiting) {
    if (visiting.length >= _kMaxBomDepth) return p.unitCost;
    if (visiting.contains(p.id)) return 0; // cycle guard

    // 1) Bundle rollup.
    if (p.isBundle && p.bundleComponents.isNotEmpty) {
      double sum = 0;
      for (final c in p.bundleComponents) {
        Product? comp;
        if (c.productId != null) {
          comp = _products.firstWhere(
            (x) => x.id == c.productId,
            orElse: () => _emptyProduct,
          );
        }
        if ((comp == null || comp.id.isEmpty) && c.shopifyVariantId != null) {
          comp = _products.firstWhere(
            (x) => (x.shopifyVariantId ?? '')
                .split(',')
                .contains(c.shopifyVariantId),
            orElse: () => _emptyProduct,
          );
        }
        if (comp != null && comp.id.isNotEmpty) {
          sum += _effectiveUnitCost(comp, {...visiting, p.id}) * c.quantity;
        }
      }
      if (sum > 0) return sum;
    }

    // 2) Manufactured product → BOM materials + production fee.
    //    BOM lines may point at raw materials OR at sub-assembly products
    //    (Phase 2.3). Sub-product cost recurses via _effectiveUnitCost.
    //    Yield loss is applied per line via [BomMaterial.effectiveQuantityPerUnit].
    final isManufactured =
        p.manufacturerId != null && p.manufacturerId!.isNotEmpty;
    if (isManufactured) {
      final bom = _boms
          .where((b) => b.finalProductId == p.id && b.isActive)
          .firstOrNull;
      if (bom != null && bom.materials.isNotEmpty) {
        final nextVisiting = {...visiting, p.id};
        // Cost contributed by one BOM line.
        double lineCost(BomMaterial m) {
          final qty = m.effectiveQuantityPerUnit;
          if (m.kind == BomComponentKind.product) {
            // Sub-assembly — roll up its own cost.
            final sub = _products.where((x) => x.id == m.refId).firstOrNull;
            if (sub != null) {
              return _effectiveUnitCost(sub, nextVisiting) * qty;
            }
            return 0;
          }
          final rm = _rawMaterials.where((r) => r.id == m.refId).firstOrNull;
          return rm != null ? rm.unitCost * qty : 0;
        }

        // Shared lines (variantId == null) are consumed by every variant.
        // Variant-specific lines are mutually exclusive, so the representative
        // product cost uses the AVERAGE of the per-variant totals rather than
        // summing them (which would overcount).
        double sharedCost = 0;
        final perVariant = <String, double>{};
        for (final m in bom.materials) {
          if (m.variantId == null) {
            sharedCost += lineCost(m);
          } else {
            perVariant[m.variantId!] =
                (perVariant[m.variantId!] ?? 0) + lineCost(m);
          }
        }
        double variantAvg = 0;
        if (perVariant.isNotEmpty) {
          variantAvg = perVariant.values.reduce((a, b) => a + b) /
              perVariant.length;
        }
        return sharedCost + variantAvg + (p.productionFee ?? 0);
      }
      // No BOM yet → fall through to manual unitCost so the row still has
      // a number (will be 0 until the user sets up the BOM).
    }

    // 3) Purchased product (or manufactured without a BOM yet).
    return p.unitCost;
  }

  static final Product _emptyProduct = Product(
    id: '',
    sku: '',
    name: '',
    category: '',
    unitCost: 0,
  );

  /// Total inventory **cost** = Σ(currentStock × effectiveUnitCost) for ACTIVE
  /// products only — keeps the number consistent with the "52 products" count
  /// shown in the dashboard subtitle (inactive products are excluded).
  double get totalStockValue => _products
      .where((p) => p.isActive)
      .fold(0, (acc, p) => acc + (p.currentStock * effectiveUnitCost(p)));

  /// Total inventory **retail value** = Σ(currentStock × sellingPrice) for
  /// ACTIVE products only. Represents potential revenue at list price.
  double get totalRetailValue => _products
      .where((p) => p.isActive)
      .fold(0, (acc, p) => acc + (p.currentStock * (p.sellingPrice ?? 0)));

  /// Margin locked in current inventory = retail − cost. Represents the
  /// gross profit still sitting on the shelf, waiting to be realised on sale.
  double get unrealizedMargin => totalRetailValue - totalStockValue;

  // ── Setup-health getters ──────────────────────────────────────────────────
  // Every KPI on the dashboard is only as honest as the data behind it. These
  // helpers let the UI nudge the user to finish product setup BEFORE trusting
  // any number. A Shopify-imported product, for example, lands with
  // unitCost = 0 — which silently distorts inventory cost, COGS, and margin.

  /// Active products whose **effective** unit cost is still 0 (Shopify or
  /// manually added without a cost). For manufactured products this checks
  /// the rolled-up BOM cost, so a product with a complete BOM counts as
  /// "cost set" even if the manual unitCost field is 0.
  List<Product> get productsMissingCost => _products
      .where((p) => p.isActive && effectiveUnitCost(p) <= 0)
      .toList(growable: false);

  /// Active products that aren't linked to a supplier AND aren't marked as
  /// manufactured. These can't be reordered automatically.
  List<Product> get productsMissingSupplier => _products
      .where((p) =>
          p.isActive &&
          (p.supplierId == null || p.supplierId!.isEmpty) &&
          (p.manufacturerId == null || p.manufacturerId!.isEmpty))
      .toList(growable: false);

  /// Active products that haven't been told how they're sourced yet — they
  /// have neither a supplier (purchased) nor a manufacturer (made in-house).
  /// Until classified, the system can't decide whether their cost comes from
  /// a supplier price or from a Bill of Materials, and the supplier-link step
  /// can't tell which products even belong in it. Bundles are excluded
  /// (their cost rolls up from components).
  List<Product> get productsNeedingSourcingType => _products
      .where((p) =>
          p.isActive &&
          !p.isBundle &&
          (p.supplierId == null || p.supplierId!.isEmpty) &&
          (p.manufacturerId == null || p.manufacturerId!.isEmpty))
      .toList(growable: false);

  /// Active products flagged as manufactured (have a manufacturerId) but
  /// missing a Bill of Materials. Without a BOM the system can't generate
  /// raw-material orders or roll up cost.
  List<Product> get manufacturedProductsMissingBom => _products
      .where((p) =>
          p.isActive &&
          (p.manufacturerId != null && p.manufacturerId!.isNotEmpty) &&
          !_boms.any((b) => b.finalProductId == p.id && b.isActive))
      .toList(growable: false);

  /// True when every active product has a cost AND every manufactured product
  /// has a BOM AND every non-manufactured product has a supplier. Drives the
  /// "Setup complete — KPIs are trustworthy" indicator on the dashboard.
  bool get productSetupHealthy =>
      productsMissingCost.isEmpty &&
      manufacturedProductsMissingBom.isEmpty &&
      productsMissingSupplier.isEmpty;

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

      // Re-key Shopify-imported demand records to the matching product.id.
      // Cloud Functions store them under "shopify_<shopifyProductId>" but the
      // products live under Firestore-generated IDs, so the forecast lookup
      // misses them. Resolve the mapping client-side.
      _remapShopifyDemand();

      await loadSettings();

      // Load Shopify connection state
      await _loadShopifyConnection();

      // Start real-time demand listener and background Shopify sync so
      // forecasts always reflect the latest sales without manual imports.
      _startDemandListener();
      _startShopifyAutoSync();
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

  /// Inspects whether a product has the supplier / manufacturer / lead-time /
  /// pricing data required to take a forecast through to a real purchase or
  /// production order. Returned object is meant to drive the UI gate on the
  /// Forecasts screen.
  ProductForecastReadiness productReadinessForForecast(String productId) {
    final product = _products.where((p) => p.id == productId).firstOrNull;
    if (product == null) {
      return ProductForecastReadiness(
        product: null,
        supplier: null,
        manufacturer: null,
        missing: const ['product'],
        hasDemandData: false,
      );
    }
    final supplier = product.supplierId != null
        ? _suppliers.where((s) => s.id == product.supplierId).firstOrNull
        : null;
    final manufacturer = product.manufacturerId != null
        ? _manufacturers.where((m) => m.id == product.manufacturerId).firstOrNull
        : null;
    final hasDemandData = (_demandByProduct[productId]?.isNotEmpty ?? false);

    final missing = <String>[];
    // A purchased product needs a supplier; a manufactured product needs a
    // manufacturer. Requiring both for every product is wrong — a product
    // linked only to a supplier should never be flagged for "missing manufacturer".
    final isManufactured = product.manufacturerId != null &&
        product.manufacturerId!.isNotEmpty;
    if (isManufactured) {
      if (manufacturer == null) missing.add('manufacturer');
    } else {
      if (supplier == null) missing.add('supplier');
    }
    if (product.leadTimeDays <= 0 &&
        (supplier?.typicalLeadTimeDays ?? 0) <= 0) {
      missing.add('leadTime');
    }
    if (product.unitCost <= 0) missing.add('unitCost');
    if (!hasDemandData) missing.add('demandData');

    return ProductForecastReadiness(
      product: product,
      supplier: supplier,
      manufacturer: manufacturer,
      missing: missing,
      hasDemandData: hasDemandData,
    );
  }

  Future<void> runForecast(
    String productId,
    String algorithm,
    int smaWindow,
    double alpha, {
    double beta = 0.1,
    double gamma = 0.2,
    List<double> wmaWeights = const [1, 2, 3],
    int seasonLength = 12,
    int? momentumWindowMonths,
  }) async {
    // ── Resolve the actual algorithm to run ────────────────────────────────
    // Special "Auto" mode picks the best algorithm based on the data shape.
    var records = _demandByProduct[productId] ?? [];
    if (records.isEmpty) {
      throw Exception(
          'No demand data found for this product. Add demand records first via the Sales History screen.');
    }

    // Momentum-window filter: keep only the most recent N monthly records.
    // When set, this is the user-chosen "how the product sells" window that
    // drives the velocity estimate. We also force the internal algorithm to
    // a simple moving average over the window so the next-period forecast
    // equals the average monthly velocity within that window.
    if (momentumWindowMonths != null && momentumWindowMonths > 0) {
      final sorted = [...records]
        ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
      if (sorted.length > momentumWindowMonths) {
        records = sorted.sublist(sorted.length - momentumWindowMonths);
      } else {
        records = sorted;
      }
      algorithm = 'SMA';
      smaWindow = records.length;
    }

    String effectiveAlgorithm = algorithm;
    if (algorithm == 'Auto') {
      effectiveAlgorithm = _autoPickAlgorithm(records, seasonLength);
    }

    // Try backend first — but with a short timeout so we don't block the user
    // when no backend is reachable. On any failure we fall back to local.
    // Skip the backend entirely in momentum-window mode so the velocity is
    // computed from the user-chosen window of records, not the full history.
    if (momentumWindowMonths == null) {
    try {
      final result = await _backendApi
          .runForecast(
            productId: productId,
            method: effectiveAlgorithm,
            windowSize: effectiveAlgorithm == 'SMA' ? smaWindow : null,
            alpha: (effectiveAlgorithm == 'SES' ||
                    effectiveAlgorithm == 'Holt' ||
                    effectiveAlgorithm == 'HoltWinters')
                ? alpha
                : null,
          )
          .timeout(const Duration(seconds: 4));
      _currentForecast = ForecastResult.fromJson(result);
      await _persistForecastResult(_currentForecast!);
      notifyListeners();
      return;
    } catch (_) {
      // Backend unavailable / slow / errored — fall back to local pure-Dart impl.
    }
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
      algorithm: effectiveAlgorithm,
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

  /// Re-maps demand records whose `productId` doesn't match any internal
  /// product to the matching product's Firestore id. Supports records keyed by
  /// "shopify_<shopifyId>", raw Shopify GIDs, or SKUs — anything that can be
  /// resolved back to a product.
  ///
  /// This fixes the upstream mismatch where the `shopifyImportOrders` Cloud
  /// Function writes demand records under "shopify_<shopifyProductId>" while
  /// the products themselves live under Firestore-generated IDs.
  void _remapShopifyDemand() {
    if (_demandByProduct.isEmpty || _products.isEmpty) return;

    final validIds = {for (final p in _products) p.id};

    // Build lookup tables for resolution.
    final byShopifyId = <String, String>{};
    final bySku = <String, String>{};
    for (final p in _products) {
      final shop = p.shopifyProductId?.toString();
      if (shop != null && shop.isNotEmpty) {
        byShopifyId[shop] = p.id;
      }
      if (p.sku.isNotEmpty) {
        bySku[p.sku.toLowerCase()] = p.id;
      }
    }

    final remapped = <String, List<DomainDemandRecord>>{};
    var moved = 0;

    _demandByProduct.forEach((key, records) {
      if (validIds.contains(key)) {
        // Already keyed by a real product.id — keep as is.
        (remapped[key] ??= []).addAll(records);
        return;
      }

      // Strip the "shopify_" prefix if present.
      String candidate = key;
      if (candidate.startsWith('shopify_')) {
        candidate = candidate.substring('shopify_'.length);
      }

      // Try Shopify ID, then SKU lookup.
      final resolved =
          byShopifyId[candidate] ?? bySku[candidate.toLowerCase()];

      if (resolved != null) {
        final fixed = records
            .map((r) => DomainDemandRecord(
                  id: r.id,
                  productId: resolved,
                  periodStart: r.periodStart,
                  quantity: r.quantity,
                  source: r.source,
                  shopifyOrderId: r.shopifyOrderId,
                ))
            .toList();
        (remapped[resolved] ??= []).addAll(fixed);
        moved += records.length;
      } else {
        // Orphan — keep under original key so it still shows in Sales History,
        // and surface the issue with a debug log.
        (remapped[key] ??= []).addAll(records);
      }
    });

    if (moved > 0) {
      // ignore: avoid_print
      print(
          '[demand] Re-keyed $moved Shopify demand record(s) to internal product IDs.');
    }

    _demandByProduct = remapped;
  }

  /// Picks the best forecasting algorithm for [records] using simple heuristics:
  /// - Not enough data (< 4 pts)            → SMA (most robust)
  /// - Detected seasonality (≥ 2 cycles)    → HoltWinters
  /// - Strong linear trend                  → Holt
  /// - Stable / mildly noisy demand         → SES
  /// - Otherwise (high noise, no trend)     → WMA
  String _autoPickAlgorithm(
      List<DomainDemandRecord> records, int seasonLength) {
    if (records.length < 4) return 'SMA';

    final sorted = [...records]
      ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
    final demand =
        sorted.map((r) => r.quantity.toDouble()).toList(growable: false);
    final n = demand.length;

    // 1. Seasonality: need at least 2 full cycles of length [seasonLength].
    if (n >= seasonLength * 2) {
      // Compute mean
      final mean = demand.reduce((a, b) => a + b) / n;
      // Compute season-index variance vs total variance
      final seasonMeans = List<double>.filled(seasonLength, 0);
      final seasonCounts = List<int>.filled(seasonLength, 0);
      for (var i = 0; i < n; i++) {
        seasonMeans[i % seasonLength] += demand[i];
        seasonCounts[i % seasonLength]++;
      }
      double seasonalVar = 0;
      for (var i = 0; i < seasonLength; i++) {
        if (seasonCounts[i] == 0) continue;
        final sm = seasonMeans[i] / seasonCounts[i];
        seasonalVar += (sm - mean) * (sm - mean);
      }
      seasonalVar /= seasonLength;
      final totalVar = demand
              .map((d) => (d - mean) * (d - mean))
              .fold<double>(0, (a, b) => a + b) /
          n;
      if (totalVar > 0 && seasonalVar / totalVar > 0.25) {
        return 'HoltWinters';
      }
    }

    // 2. Trend: linear regression slope significance.
    final mean = demand.reduce((a, b) => a + b) / n;
    final xs = List<double>.generate(n, (i) => i.toDouble());
    final xMean = (n - 1) / 2.0;
    double num = 0, den = 0;
    for (var i = 0; i < n; i++) {
      num += (xs[i] - xMean) * (demand[i] - mean);
      den += (xs[i] - xMean) * (xs[i] - xMean);
    }
    final slope = den == 0 ? 0 : num / den;
    // Slope per period vs mean — if abs(slope) > 2% of mean per period → trend
    if (mean > 0 && (slope.abs() / mean) > 0.02) {
      return 'Holt';
    }

    // 3. Noise level: coefficient of variation
    final variance = demand
            .map((d) => (d - mean) * (d - mean))
            .fold<double>(0, (a, b) => a + b) /
        n;
    final stdDev = variance > 0 ? sqrt(variance) : 0.0;
    final cv = mean > 0 ? stdDev / mean : 0.0;

    if (cv < 0.35) return 'SES'; // Smooth, stable demand
    return 'WMA'; // Volatile demand — weighted average dampens noise
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
      _remapShopifyDemand();
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
    final activeProducts = _products.where((p) => p.isActive).toList();
    _recommendations = _replenishmentService.buildRecommendations(
      products: activeProducts,
      demandByProduct: _demandByProduct,
      suppliers: supplierMap,
      settings: _settings,
    );
    // Keep ABC-XYZ classification in sync with the latest demand + product set
    // so the matrix is always available without needing a manual refresh.
    _abcXyzMatrix = _abcXyzService.buildMatrix(
      products: activeProducts,
      demandByProduct: _demandByProduct,
    );
    computeMinimumStockLevels();
  }

  void computeMinimumStockLevels() {
    _minimumStockResults = _minimumStockService.computeAll(
      products: _products.where((p) => p.isActive).toList(),
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
    // Start background auto-sync once the store is connected.
    _startShopifyAutoSync();
    notifyListeners();
  }

  Future<void> disconnectShopify() async {
    _shopifyAutoSyncTimer?.cancel();
    _shopifyAutoSyncTimer = null;
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

  /// Imports only the Shopify products whose IDs are in [selectedIds].
  /// Uses the same SKU-based deduplication as [importShopifyProducts].
  Future<Map<String, int>> importSelectedShopifyProducts(
      List<String> selectedIds) async {
    if (_shopifyService == null || selectedIds.isEmpty) {
      return {'newCount': 0, 'mergedCount': 0, 'totalImported': 0};
    }
    // Call the Cloud Function with only the selected doc IDs — it writes
    // those products to Firestore and returns the merged data.
    final toImport =
        await (_shopifyService as dynamic).importSelectedFromShopify(selectedIds)
            as List<Product>;
    int newCount = 0;
    int mergedCount = 0;

    for (final p in toImport) {
      // Match by Firestore ID first, then by SKU (handles legacy local products
      // that share a SKU with a newly-imported Shopify product).
      final idIdx = _products.indexWhere((e) => e.id == p.id);
      final skuIdx = idIdx == -1 && p.sku.isNotEmpty
          ? _products.indexWhere((e) => e.sku == p.sku)
          : -1;

      if (idIdx != -1) {
        // Update only Shopify-sourced fields; preserve user-configured fields
        // (supplierId, manufacturerId, warehouseId, leadTimeDays, etc.).
        final e = _products[idIdx];
        _products[idIdx] = e.copyWith(
          sku: p.sku.isNotEmpty ? p.sku : null,
          name: p.name.isNotEmpty ? p.name : null,
          category: p.category.isNotEmpty ? p.category : null,
          currentStock: p.currentStock,
          imageUrl: p.imageUrl,
          sellingPrice: p.sellingPrice,
          shopifyProductId: p.shopifyProductId,
          shopifyVariantId: p.shopifyVariantId,
          isActive: p.isActive,
        );
        mergedCount++;
      } else if (skuIdx != -1) {
        final e = _products[skuIdx];
        _products[skuIdx] = e.copyWith(
          currentStock: p.currentStock,
          imageUrl: p.imageUrl,
          sellingPrice: p.sellingPrice,
          shopifyProductId: p.shopifyProductId,
          shopifyVariantId: p.shopifyVariantId,
          isActive: p.isActive,
        );
        mergedCount++;
      } else {
        _products.add(p);
        newCount++;
      }
    }
    _rebuildRecommendations();
    notifyListeners();
    return {
      'newCount': newCount,
      'mergedCount': mergedCount,
      'totalImported': toImport.length,
    };
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
      _remapShopifyDemand();
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

  /// Subscribes to the `demandRecords` Firestore collection so the app
  /// reacts instantly when new sales arrive (e.g. via the Shopify
  /// `orders/create` webhook) or when records are added/edited elsewhere.
  void _startDemandListener() {
    if (_repo == null) return;
    _demandSub?.cancel();
    _demandSub = _repo!.watchDemandHistory().listen(
      (snapshot) {
        _demandByProduct = snapshot;
        _remapShopifyDemand();
        _rebuildRecommendations();
        notifyListeners();
      },
      onError: (e) {
        // Silent — listener errors are non-fatal; manual reload still works.
        debugPrint('[demand] watch error: $e');
      },
    );
  }

  /// Silently pulls the latest Shopify orders right after login and then
  /// every 10 minutes while the app is running, so demand data stays
  /// up to date even when webhooks are not configured. UI snackbars are
  /// only shown for the explicit "Import Shopify Orders" button path.
  void _startShopifyAutoSync() {
    _shopifyAutoSyncTimer?.cancel();
    if (_shopifyService == null || _shopifyConnection?.isConnected != true) {
      return;
    }
    // Kick off an immediate background sync (don't block UI).
    unawaited(_silentShopifySync());
    _shopifyAutoSyncTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => unawaited(_silentShopifySync()),
    );
  }

  Future<void> _silentShopifySync() async {
    if (_shopifyService == null || _shopifyConnection?.isConnected != true) {
      return;
    }
    if (_shopifySyncInProgress) return;
    _shopifySyncInProgress = true;
    _lastShopifySyncError = null;
    notifyListeners();
    try {
      final result = await _shopifyService!.importOrderHistory();
      _lastShopifySyncResult = result;
      _lastShopifySyncAt = DateTime.now();
      debugPrint('[shopify] auto-sync ok: $result');
      // No need to reload demand here — the Firestore listener will pick
      // up any new records and refresh the UI automatically.
    } catch (e) {
      _lastShopifySyncError = e.toString();
      _lastShopifySyncAt = DateTime.now();
      debugPrint('[shopify] auto-sync failed: $e');
    } finally {
      _shopifySyncInProgress = false;
      notifyListeners();
    }
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
      // poNumber is assigned in saveDraftOrder or confirmPurchaseOrder
    );
  }

  /// Save a purchase order as draft (not yet confirmed).
  Future<PurchaseOrder?> saveDraftOrder(PurchaseOrder order) async {
    if (_repo == null) return null;
    try {
      order.status = OrderStatus.draft;
      if (order.poNumber == null) {
        // Assign a sequential PO number if not already set
        final po = PurchaseOrder(
          id: order.id,
          status: order.status,
          createdAt: order.createdAt,
          createdByUid: order.createdByUid,
          createdByName: order.createdByName,
          items: order.items,
          notes: order.notes,
          poNumber: await _nextPoNumber(),
        );
        final saved = await _repo!.addPurchaseOrder(po);
        _purchaseOrders.insert(0, saved);
        notifyListeners();
        return saved;
      }
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
      // Assign PO number now if it wasn't set when drafted
      final PurchaseOrder toSave;
      if (order.poNumber == null) {
        final poNum = await _nextPoNumber();
        toSave = PurchaseOrder(
          id: order.id,
          status: order.status,
          createdAt: order.createdAt,
          createdByUid: order.createdByUid,
          createdByName: order.createdByName,
          items: order.items,
          notes: order.notes,
          poNumber: poNum,
        );
      } else {
        toSave = order;
      }
      final saved = await _repo!.addPurchaseOrder(toSave);

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

  /// Generate the next sequential PO number in format "PO-YYYY-NNNN".
  /// Uses a Firestore counter document under `users/{uid}/settings/poCounter`
  /// with an atomic increment to avoid duplicate numbers.
  Future<String> _nextPoNumber() async {
    if (_currentUser == null) {
      return 'PO-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch % 10000}';
    }
    final year = DateTime.now().year;
    final counterRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('settings')
        .doc('poCounter');

    final snap = await counterRef.get();
    final data = snap.data() ?? {};
    final lastYear = data['year'] as int? ?? 0;
    final lastSeq = (lastYear == year ? (data['seq'] as int? ?? 0) : 0);
    final nextSeq = lastSeq + 1;
    await counterRef.set({'year': year, 'seq': nextSeq});
    return 'PO-$year-${nextSeq.toString().padLeft(4, '0')}';
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

  /// Mark a raw-material purchase order as received: set its status to
  /// `received` and increment on-hand stock for each line item's raw material.
  Future<void> receiveRawMaterialPurchaseOrder(String orderId) async {
    if (_currentUser == null) return;
    final idx = _rmPurchaseOrders.indexWhere((o) => o.id == orderId);
    if (idx == -1) return;
    final order = _rmPurchaseOrders[idx];
    order.status = 'received';

    // Add the received quantities into raw-material stock.
    for (final item in order.items) {
      final rmIdx =
          _rawMaterials.indexWhere((r) => r.id == item.rawMaterialId);
      if (rmIdx == -1) continue;
      _rawMaterials[rmIdx].currentStock += item.quantityOrdered.round();
      if (_repo != null) {
        await _repo!.updateRawMaterial(_rawMaterials[rmIdx]);
      }
    }

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('rawMaterialPurchaseOrders')
        .doc(orderId);
    await ref.update({'status': 'received'});
    notifyListeners();
  }

  /// After a raw-material purchase order has been received, dispatch the
  /// materials to the manufacturer responsible for the finished product so
  /// they can begin production. Creates a [ProductionOrder], a manufacturer
  /// portal order (so the materials show in the manufacturer's portal/email),
  /// and emails the manufacturer. Returns the created order.
  ///
  /// Throws an [Exception] with a user-facing message when the order is not
  /// linked to a product or the product has no manufacturer assigned.
  Future<ProductionOrder?> sendReceivedRawMaterialsToManufacturer(
    RawMaterialPurchaseOrder rmOrder,
  ) async {
    if (_currentUser == null ||
        _manufacturingService == null ||
        _firestoreRepo == null) {
      return null;
    }

    final productId = rmOrder.forecastProductId;
    if (productId == null || productId.isEmpty) {
      throw Exception(
        'This raw-material order is not linked to a product, so it cannot '
        'be sent to a manufacturer.',
      );
    }
    final product = _products.where((p) => p.id == productId).firstOrNull;
    if (product == null) {
      throw Exception('The linked product could not be found.');
    }
    final manufacturerId = product.manufacturerId ?? '';
    if (manufacturerId.isEmpty) {
      throw Exception(
        'Product "${product.name}" has no manufacturer assigned. '
        'Assign one in Products → Edit, then try again.',
      );
    }

    // Determine how many finished units these received materials support,
    // using the product's BOM. Falls back to one batch when unavailable.
    final bom = _boms
            .where((b) => b.finalProductId == productId && b.isActive)
            .firstOrNull ??
        _boms.where((b) => b.finalProductId == productId).firstOrNull;
    int producibleQty = 0;
    if (bom != null && bom.materials.isNotEmpty) {
      final relevant = bom.materials
          .where((mat) =>
              rmOrder.items.any((it) => it.rawMaterialId == mat.rawMaterialId))
          .toList();
      for (final mat in relevant) {
        if (mat.quantityPerUnit <= 0) continue;
        final received = rmOrder.items
            .where((it) => it.rawMaterialId == mat.rawMaterialId)
            .fold<double>(0, (acc, it) => acc + it.quantityOrdered);
        final canMake = (received / mat.quantityPerUnit).floor();
        if (producibleQty == 0 || canMake < producibleQty) {
          producibleQty = canMake;
        }
      }
    }
    if (producibleQty <= 0) producibleQty = 1;

    final estimatedCost = rmOrder.totalCost;

    // Create the production order and notify the manufacturer.
    final order = await _manufacturingService!.createProductionOrder(
      finalProductId: productId,
      quantity: producibleQty,
      manufacturerId: manufacturerId,
      estimatedCost: estimatedCost,
    );
    _productionOrders.insert(0, order);

    // Build a manufacturer portal order from the received materials so the
    // manufacturer email/portal lists what they are receiving.
    final mfr =
        _manufacturers.where((m) => m.id == manufacturerId).firstOrNull;
    final rmOrdersData = rmOrder.items
        .map((it) => {
              'materialName': it.rawMaterialName,
              'quantity': it.quantityOrdered,
              'unit': it.unitOfMeasure,
              'status': 'received',
              'supplierName': rmOrder.supplierName,
            })
        .toList();
    await _firestoreRepo!.addManufacturerOrder({
      'productionOrderId': order.id,
      'productName': product.name,
      'quantity': order.quantity,
      'estimatedCost': order.estimatedCost,
      'manufacturerId': manufacturerId,
      'manufacturerName': mfr?.name ?? '',
      'manufacturerEmail': mfr?.contactEmail ?? '',
      'status': 'pending',
      'accessToken': _generateAccessToken(),
      'rawMaterialOrders': rmOrdersData,
      'incomingSuppliers': [rmOrder.supplierName],
      'expiresAt':
          Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
    });

    // Materials are already in hand → mark the production order ready.
    if (_workflowService != null) {
      await _workflowService!.transitionProductionOrder(
        order,
        ProductionOrderStatus.materialsReady,
        _currentUser!.uid,
      );
    }

    try {
      await _invokeCloudFunction(
        CloudFunctionConfig.sendManufacturerEmails,
        {'uid': _currentUser!.uid, 'productionOrderId': order.id},
      );
    } catch (e) {
      debugPrint(
          '[sendReceivedRawMaterialsToManufacturer] email failed: $e');
    }

    notifyListeners();
    return order;
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

/// Result of inspecting a product for forecast prerequisites.
class ProductForecastReadiness {
  final Product? product;
  final Supplier? supplier;
  final Manufacturer? manufacturer;

  /// Codes of missing prerequisites. Possible values:
  /// 'product', 'supplier', 'manufacturer', 'leadTime', 'unitCost',
  /// 'demandData'.
  final List<String> missing;
  final bool hasDemandData;

  ProductForecastReadiness({
    required this.product,
    required this.supplier,
    required this.manufacturer,
    required this.missing,
    required this.hasDemandData,
  });

  bool get isReady => missing.isEmpty;

  /// Can run the forecast computation (demand data + cost + lead time).
  bool get canCompute =>
      !missing.contains('demandData') &&
      !missing.contains('unitCost') &&
      !missing.contains('leadTime');

  /// Can dispatch the order (all missing items must be supplier/manufacturer only).
  bool get canDispatch =>
      canCompute &&
      missing.every((m) => m == 'supplier' || m == 'manufacturer');

  /// Items blocking compute (demand data, cost, lead time).
  List<String> get missingForCompute =>
      missing.where((m) => m == 'demandData' || m == 'unitCost' || m == 'leadTime').toList();

  /// Items blocking dispatch (supplier/manufacturer contact info).
  List<String> get missingForDispatch =>
      missing.where((m) => m == 'supplier' || m == 'manufacturer').toList();

  /// Resolved lead time: product > supplier > 0.
  int get effectiveLeadTimeDays {
    if ((product?.leadTimeDays ?? 0) > 0) return product!.leadTimeDays;
    return supplier?.typicalLeadTimeDays ?? 0;
  }

  String labelFor(String code) {
    switch (code) {
      case 'product':
        return 'Product';
      case 'supplier':
        return 'Supplier link';
      case 'manufacturer':
        return 'Manufacturer link';
      case 'leadTime':
        return 'Lead time (days)';
      case 'unitCost':
        return 'Unit cost / pricing';
      case 'demandData':
        return 'Sales / demand history';
      default:
        return code;
    }
  }
}
