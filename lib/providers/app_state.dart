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
import 'package:ma5zony/services/backend_api_service.dart';
import 'package:ma5zony/utils/cloud_function_config.dart';

/// Central application state ChangeNotifier.
/// Composes all domain services and exposes reactive state to the UI.
class AppState extends ChangeNotifier {
  // ── Services ───────────────────────────────────────────────────────────────
  InventoryRepository? _repo;
  SettingsService? _settingsService;
  FirebaseShopifyService? _shopifyService;
  NotificationService? _notificationService;
  StreamSubscription<List<AppNotification>>? _notifSub;
  late final ForecastingService _forecastingService;
  late final InventoryPolicyService _policyService;
  late final ReplenishmentService _replenishmentService;
  late final FirebaseAuthService _authService;
  late final RecommendationEngineService _recEngine;
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
    _authService = FirebaseAuthService();
    _recEngine = RecommendationEngineService();

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
  ShopifyStoreConnection? _shopifyConnection;
  UserSettings _settings = const UserSettings();
  Set<String> _approvedRecommendations = {};
  List<AppUser> _teamMembers = [];
  List<PurchaseOrder> _purchaseOrders = [];
  List<SupplierOrder> _supplierOrders = [];

  // Supply-chain state (Phase 1–3)
  List<RawMaterial> _rawMaterials = [];
  List<BillOfMaterials> _boms = [];
  List<Manufacturer> _manufacturers = [];
  List<ProductionOrder> _productionOrders = [];
  List<RawMaterialOrder> _rawMaterialOrders = [];
  List<ManufacturingRecommendation> _mfgRecommendations = [];
  List<CashFlowSnapshot> _cashFlowSnapshots = [];
  List<WorkflowLog> _workflowLogs = [];

  List<Product> get products => _products;
  List<Warehouse> get warehouses => _warehouses;
  List<Supplier> get suppliers => _suppliers;
  Map<String, List<DomainDemandRecord>> get demandByProduct => _demandByProduct;
  List<ReplenishmentRecommendation> get recommendations => _recommendations;
  ForecastResult? get currentForecast => _currentForecast;
  ShopifyStoreConnection? get shopifyConnection => _shopifyConnection;
  UserSettings get settings => _settings;
  Set<String> get approvedRecommendations => _approvedRecommendations;
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

  Future<void> deleteProduct(String productId) async {
    try {
      // Cascade: delete associated demand records
      final records = _demandByProduct[productId] ?? [];
      for (final r in records) {
        await _repo!.deleteDemandRecord(r.id);
      }
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
          );
          await _repo!.updateProduct(updated);
          _products[i] = updated;
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

  Future<void> approveRecommendation(ReplenishmentRecommendation rec) async {
    if (_repo == null || _currentUser == null) return;
    // Store approval under users/{uid}/approvals/{productId}
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('approvals')
        .doc(rec.productId)
        .set({
      'productId': rec.productId,
      'productName': rec.productName,
      'sku': rec.sku,
      'suggestedOrderQty': rec.suggestedOrderQty,
      'approvedAt': FieldValue.serverTimestamp(),
    });
    _approvedRecommendations.add(rec.productId);
    notifyListeners();
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
    if (result == 'success') {
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

  /// Number of products at or below their computed reorder point.
  int get lowStockItems => _recommendations.length;

  /// Open replenishment recommendations count.
  int get openRecommendations => _recommendations.length;

  /// Forecast accuracy = 1 – MAPE (0.0 when no forecast has been run yet).
  double get forecastAccuracy =>
      _currentForecast?.mape != null ? 1 - _currentForecast!.mape! : 0.0;

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

      // Check for stock alerts (fire-and-forget)
      _checkStockAlerts();
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
    double alpha,
  ) async {
    // Try backend first
    try {
      final result = await _backendApi.runForecast(
        productId: productId,
        method: algorithm,
        windowSize: algorithm == 'SMA' ? smaWindow : null,
        alpha: algorithm == 'SES' ? alpha : null,
      );
      _currentForecast = ForecastResult.fromJson(result);
      notifyListeners();
      return;
    } catch (_) {
      // Backend unavailable — fall back to local
    }

    final records = _demandByProduct[productId] ?? [];
    if (records.isEmpty) return;

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
    );

    notifyListeners();
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

  Future<void> importShopifyProducts() async {
    if (_shopifyService == null) return;
    final imported = await _shopifyService!.importProductsFromShopify();
    // Merge into local state
    for (final p in imported) {
      final idx = _products.indexWhere((e) => e.id == p.id);
      if (idx != -1) {
        _products[idx] = p;
      } else {
        _products.add(p);
      }
    }
    _rebuildRecommendations();
    notifyListeners();
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
    if (_currentUser == null) return null;

    rec.status = RecommendationStatus.approved;
    await _repo!.updateManufacturingRecommendation(rec);

    // Try backend-driven atomic workflow first
    try {
      final poJson = await _backendApi.createProductionOrder(
        finalProductId: rec.productId,
        quantity: rec.suggestedQty,
        manufacturerId: manufacturerId,
        estimatedCost: rec.estimatedCost,
      );
      final orderId = poJson['id'] as String;

      // Approve + auto-create raw material orders atomically on the backend
      final approvedJson = await _backendApi.approveProductionOrder(orderId);
      final order = ProductionOrder.fromFirestore(
        approvedJson['id'] as String,
        approvedJson,
      );
      _productionOrders.insert(0, order);

      // Reload raw material orders created by backend
      _rawMaterialOrders = await _repo!.getRawMaterialOrders();

      // Create portal orders and trigger emails (frontend-side)
      await _createFactoryPortalOrders(order);

      notifyListeners();
      return order;
    } catch (_) {
      // Backend unavailable — fall back to local workflow
    }

    // Fallback: local workflow
    if (_manufacturingService == null) return null;

    final order = await _manufacturingService!.createProductionOrder(
      finalProductId: rec.productId,
      quantity: rec.suggestedQty,
      manufacturerId: manufacturerId,
      estimatedCost: rec.estimatedCost,
    );
    _productionOrders.insert(0, order);

    // Auto-generate raw-material orders if BOM exists
    final bom = _boms.where((b) => b.finalProductId == rec.productId).firstOrNull;
    if (bom != null) {
      final rmOrders = await _manufacturingService!.generateRawMaterialOrders(
        productionOrder: order,
        bom: bom,
        rawMaterials: _rawMaterials,
      );
      _rawMaterialOrders.addAll(rmOrders);
      await _createFactoryPortalOrders(order);

      // Transition to materials_ordered
      await _workflowService!.transitionProductionOrder(
        order,
        ProductionOrderStatus.materialsOrdered,
        _currentUser!.uid,
      );
    }

    notifyListeners();
    return order;
  }

  /// Creates top-level factoryOrders for portal access and triggers emails.
  Future<void> _createFactoryPortalOrders(ProductionOrder order) async {
    final firestoreRepo = _firestoreRepo;
    if (firestoreRepo == null || _currentUser == null) return;

    final orderRmOrders = _rawMaterialOrders
        .where((o) => o.productionOrderId == order.id)
        .toList();

    for (final rmo in orderRmOrders) {
      final rm = _rawMaterials
          .where((r) => r.id == rmo.rawMaterialId)
          .firstOrNull;
      final supplier = _suppliers
          .where((s) => s.id == rmo.supplierId)
          .firstOrNull;

      await firestoreRepo.addFactoryOrder({
        'productionOrderId': order.id,
        'rawMaterialOrderId': rmo.id,
        'rawMaterialId': rmo.rawMaterialId,
        'materialName': rm?.name ?? '',
        'quantity': rmo.quantity,
        'unit': rm?.unit ?? 'pcs',
        'supplierId': rmo.supplierId,
        'supplierName': supplier?.name ?? '',
        'supplierEmail': supplier?.contactEmail ?? '',
        'status': 'pending',
        'requestedDate': Timestamp.fromDate(rmo.requestedDate),
        'accessToken': rmo.accessToken,
        'expiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 30))),
      });
    }

    // Fire-and-forget: send factory emails
    _callCloudFunction(
      CloudFunctionConfig.sendFactoryEmails,
      {'uid': _currentUser!.uid, 'productionOrderId': order.id},
    );
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
      if (newStatus == ProductionOrderStatus.completed) {
        final product = _products.where((p) => p.id == order.finalProductId).firstOrNull;
        if (product != null) {
          product.currentStock += order.quantity;
        }
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

    if (newStatus == ProductionOrderStatus.completed) {
      final product = _products.where((p) => p.id == order.finalProductId).firstOrNull;
      if (product != null) {
        product.currentStock += order.quantity;
        await _repo!.updateProduct(product);
      }
    }

    notifyListeners();
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

  // ── Cloud Function Helpers ─────────────────────────────────────────────────

  /// Fire-and-forget call to a Cloud Function endpoint.
  void _callCloudFunction(String url, Map<String, dynamic> body) {
    Future(() async {
      final user = _authService.currentUser;
      final token = await user?.getIdToken();
      await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
    }).catchError((_) {});
  }
}
