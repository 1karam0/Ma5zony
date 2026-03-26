import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ma5zony/models/app_notification.dart';
import 'package:ma5zony/models/app_user.dart';
import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/forecast_result.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/replenishment_recommendation.dart';
import 'package:ma5zony/models/shopify_store_connection.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/models/warehouse.dart';
import 'package:ma5zony/services/firebase_auth_service.dart';
import 'package:ma5zony/services/firestore_inventory_repository.dart';
import 'package:ma5zony/services/forecasting_service.dart';
import 'package:ma5zony/services/inventory_policy_service.dart';
import 'package:ma5zony/services/inventory_repository.dart';
import 'package:ma5zony/services/replenishment_service.dart';
import 'package:ma5zony/services/settings_service.dart';
import 'package:ma5zony/services/firebase_shopify_service.dart';
import 'package:ma5zony/services/notification_service.dart';

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

  AppState() {
    _forecastingService = ForecastingService();
    _policyService = InventoryPolicyService();
    _replenishmentService = ReplenishmentService(
      forecastingService: _forecastingService,
      policyService: _policyService,
    );
    _authService = FirebaseAuthService();

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
    _startNotificationListener();
  }

  // ── Auth State ─────────────────────────────────────────────────────────────
  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;

  String? _authError;
  String? get authError => _authError;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  void _onAuthStateChanged(dynamic firebaseUser) async {
    if (firebaseUser == null) {
      _currentUser = null;
      _repo = null;
      _settingsService = null;
      _shopifyService = null;
      _clearDomainState();
    } else {
      // Fetch the Firestore user profile.
      final profile = await _authService.getUserProfile(firebaseUser.uid);
      if (profile != null) {
        _currentUser = AppUser.fromFirestore(firebaseUser.uid, profile);
      } else {
        // Fallback when profile doc hasn't been created yet.
        _currentUser = AppUser(
          uid: firebaseUser.uid,
          name: firebaseUser.displayName ?? '',
          email: firebaseUser.email ?? '',
          role: 'Inventory Manager',
        );
      }
      _initRepo(firebaseUser.uid);
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
  }

  Future<bool> login(String email, String password) async {
    _authError = null;
    try {
      final user = await _authService.login(email, password);
      if (user != null) {
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
        _initRepo(user.uid);
        notifyListeners();
        return true;
      }
      return false;
    } on Exception catch (e) {
      _authError = _parseFirebaseError(e);
      notifyListeners();
      return false;
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
        notifyListeners();
        return true;
      }
      return false;
    } on Exception catch (e) {
      _authError = _parseFirebaseError(e);
      notifyListeners();
      return false;
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
      _products.fold(0, (sum, p) => sum + (p.currentStock * p.unitCost));

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
    final imported = result['imported'] as int? ?? 0;
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
}
