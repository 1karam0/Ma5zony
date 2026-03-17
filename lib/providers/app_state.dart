import 'package:flutter/material.dart';
import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/forecast_result.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/replenishment_recommendation.dart';
import 'package:ma5zony/models/shopify_store_connection.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/models/warehouse.dart';
import 'package:ma5zony/services/forecasting_service.dart';
import 'package:ma5zony/services/inventory_policy_service.dart';
import 'package:ma5zony/services/mock_inventory_repository.dart';
import 'package:ma5zony/services/replenishment_service.dart';
import 'package:ma5zony/services/shopify_integration_service.dart';

// Re-export User from app_models for auth
import 'package:ma5zony/models/app_models.dart' show User;

/// Central application state ChangeNotifier.
/// Composes all domain services and exposes reactive state to the UI.
class AppState extends ChangeNotifier {
  // ── Services ───────────────────────────────────────────────────────────────
  late final MockInventoryRepository _repo;
  late final ForecastingService _forecastingService;
  late final InventoryPolicyService _policyService;
  late final ReplenishmentService _replenishmentService;
  late final ShopifyIntegrationService _shopifyService;

  AppState() {
    _repo = MockInventoryRepository();
    _forecastingService = ForecastingService();
    _policyService = InventoryPolicyService();
    _replenishmentService = ReplenishmentService(
      forecastingService: _forecastingService,
      policyService: _policyService,
    );
    _shopifyService = MockShopifyIntegrationService(repository: _repo);
  }

  // ── Auth State ─────────────────────────────────────────────────────────────
  User? _currentUser;
  User? get currentUser => _currentUser;

  Future<bool> login(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (email.isNotEmpty && password.isNotEmpty) {
      _currentUser = User(
        id: 'u1',
        name: 'Demo User',
        email: email,
        role: 'Inventory Manager',
      );
      notifyListeners();
      return true;
    }
    return false;
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }

  Future<void> register(
    String name,
    String email,
    String password,
    String role,
  ) async {
    await Future.delayed(const Duration(milliseconds: 600));
    _currentUser = User(id: 'u2', name: name, email: email, role: role);
    notifyListeners();
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

  List<Product> get products => _products;
  List<Warehouse> get warehouses => _warehouses;
  List<Supplier> get suppliers => _suppliers;
  Map<String, List<DomainDemandRecord>> get demandByProduct => _demandByProduct;
  List<ReplenishmentRecommendation> get recommendations => _recommendations;
  ForecastResult? get currentForecast => _currentForecast;
  ShopifyStoreConnection? get shopifyConnection => _shopifyConnection;

  // ── Computed KPIs ──────────────────────────────────────────────────────────

  /// Total inventory value = Σ(currentStock × unitCost)
  double get totalStockValue =>
      _products.fold(0, (sum, p) => sum + (p.currentStock * p.unitCost));

  /// Number of products at or below their computed reorder point.
  int get lowStockItems => _recommendations.length;

  /// Open replenishment recommendations count.
  int get openRecommendations => _recommendations.length;

  /// Forecast accuracy = 1 – MAPE (falls back to 0.85 when no forecast run yet).
  double get forecastAccuracy =>
      _currentForecast?.mape != null ? 1 - _currentForecast!.mape! : 0.85;

  // ── Load All Data ──────────────────────────────────────────────────────────

  Future<void> loadAll() async {
    _isLoading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repo.getProducts(),
        _repo.getWarehouses(),
        _repo.getSuppliers(),
        _repo.getDemandHistory(),
        _shopifyService.getCurrentConnection(),
      ]);

      _products = results[0] as List<Product>;
      _warehouses = results[1] as List<Warehouse>;
      _suppliers = results[2] as List<Supplier>;
      _demandByProduct = results[3] as Map<String, List<DomainDemandRecord>>;
      _shopifyConnection = results[4] as ShopifyStoreConnection;

      _rebuildRecommendations();
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
    );
  }

  // ── Shopify ────────────────────────────────────────────────────────────────

  Future<void> connectShopify(String shopDomain) async {
    _shopifyConnection = await _shopifyService.connectStore(
      shopDomain: shopDomain,
    );
    notifyListeners();
  }

  Future<void> disconnectShopify() async {
    await _shopifyService.disconnectStore();
    _shopifyConnection = await _shopifyService.getCurrentConnection();
    notifyListeners();
  }

  Future<void> importShopifyProducts() async {
    await _shopifyService.importProductsFromShopify();
    _products = await _repo.getProducts();
    _rebuildRecommendations();
    notifyListeners();
  }

  Future<void> syncShopifyInventory() async {
    await _shopifyService.syncInventoryFromShopify();
    _shopifyConnection = await _shopifyService.getCurrentConnection();
    notifyListeners();
  }
}
