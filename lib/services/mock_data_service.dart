import 'dart:math';
import 'package:flutter/material.dart';
import 'package:ma5zony/models/app_models.dart';

class MockDataService extends ChangeNotifier {
  // Singleton
  static final MockDataService _instance = MockDataService._internal();
  factory MockDataService() => _instance;
  MockDataService._internal() {
    _seedData();
  }

  // State
  User? _currentUser;
  List<Product> _products = [];
  List<Supplier> _suppliers = [];
  List<Warehouse> _warehouses = [];
  List<DemandRecord> _demandHistory = [];
  List<ForecastRecord> _forecasts = [];

  // Getters
  User? get currentUser => _currentUser;
  List<Product> get products => _products;
  List<Supplier> get suppliers => _suppliers;
  List<Warehouse> get warehouses => _warehouses;
  List<DemandRecord> get demandHistory => _demandHistory;
  List<ForecastRecord> get forecasts => _forecasts;

  // KPIs
  double get totalStockValue =>
      _products.fold(0, (sum, p) => sum + (p.currentStock * p.standardCost));
  int get lowStockItems =>
      _products.where((p) => p.currentStock <= p.reorderPoint).length;
  int get openRecommendations => _products
      .where((p) => p.currentStock <= p.reorderPoint)
      .length; // Simplified
  double get forecastAccuracy => 0.85; // Mock

  // Auth Methods
  Future<bool> login(String email, String password) async {
    await Future.delayed(const Duration(seconds: 1)); // Simulate network
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
    await Future.delayed(const Duration(seconds: 1));
    _currentUser = User(id: 'u2', name: name, email: email, role: role);
    notifyListeners();
  }

  // Data Methods
  void addProduct(Product product) {
    _products.add(product);
    notifyListeners();
  }

  void updateProduct(Product product) {
    final index = _products.indexWhere((p) => p.id == product.id);
    if (index != -1) {
      _products[index] = product;
      notifyListeners();
    }
  }

  void deleteProduct(String id) {
    _products.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  void addSupplier(Supplier supplier) {
    _suppliers.add(supplier);
    notifyListeners();
  }

  void importShopifyProducts() {
    // Mock import
    _products.addAll([
      Product(
        id: 'sp1',
        sku: 'SH-001',
        name: 'Shopify T-Shirt',
        category: 'Apparel',
        uom: 'pcs',
        standardCost: 15.0,
        defaultSupplierId: 's1',
        currentStock: 100,
        reorderPoint: 20,
      ),
      Product(
        id: 'sp2',
        sku: 'SH-002',
        name: 'Shopify Mug',
        category: 'Accessories',
        uom: 'pcs',
        standardCost: 5.0,
        defaultSupplierId: 's1',
        currentStock: 50,
        reorderPoint: 10,
      ),
    ]);
    notifyListeners();
  }

  // Forecasting Logic (Mock)
  void runForecast(
    String productId,
    String algorithm,
    int period,
    double alpha,
  ) {
    // Generate dummy forecast data based on parameters
    _forecasts = List.generate(12, (index) {
      return ForecastRecord(
        period: DateTime.now().add(Duration(days: index * 30)),
        actual: index < 6 ? 100 + Random().nextInt(50) : 0,
        forecast: 100 + Random().nextInt(30),
        error: index < 6 ? Random().nextDouble() * 10 : 0,
      );
    });
    notifyListeners();
  }

  void _seedData() {
    _suppliers = [
      Supplier(
        id: 's1',
        name: 'Alpha Supply Co.',
        contactPerson: 'John Doe',
        email: 'john@alpha.com',
        phone: '123-456-7890',
        leadTimeDays: 5,
        notes: 'Reliable',
      ),
      Supplier(
        id: 's2',
        name: 'Beta Logistics',
        contactPerson: 'Jane Smith',
        email: 'jane@beta.com',
        phone: '987-654-3210',
        leadTimeDays: 14,
        notes: 'Cheaper but slower',
      ),
    ];

    _warehouses = [
      Warehouse(id: 'w1', name: 'Main Warehouse', location: 'New York, NY'),
      Warehouse(id: 'w2', name: 'West Coast Hub', location: 'Los Angeles, CA'),
    ];

    _products = [
      Product(
        id: 'p1',
        sku: 'SKU-001',
        name: 'Cotton T-Shirt',
        category: 'Apparel',
        uom: 'pcs',
        standardCost: 12.50,
        defaultSupplierId: 's1',
        currentStock: 150,
        reorderPoint: 50,
        safetyStock: 20,
      ),
      Product(
        id: 'p2',
        sku: 'SKU-002',
        name: 'Denim Jeans',
        category: 'Apparel',
        uom: 'pcs',
        standardCost: 25.00,
        defaultSupplierId: 's2',
        currentStock: 40,
        reorderPoint: 60,
        safetyStock: 30,
      ), // Low stock
      Product(
        id: 'p3',
        sku: 'SKU-003',
        name: 'Leather Belt',
        category: 'Accessories',
        uom: 'pcs',
        standardCost: 15.00,
        defaultSupplierId: 's1',
        currentStock: 200,
        reorderPoint: 30,
        safetyStock: 10,
      ),
      Product(
        id: 'p4',
        sku: 'SKU-004',
        name: 'Sneakers',
        category: 'Footwear',
        uom: 'pair',
        standardCost: 45.00,
        defaultSupplierId: 's2',
        currentStock: 5,
        reorderPoint: 20,
        safetyStock: 10,
      ), // Critical
    ];

    _demandHistory = List.generate(
      20,
      (index) => DemandRecord(
        id: 'd$index',
        productId: 'p1',
        date: DateTime.now().subtract(Duration(days: index * 7)),
        quantity: 50 + Random().nextInt(50),
        source: 'Imported',
      ),
    );

    // Initial forecast run
    runForecast('p1', 'SMA', 3, 0.5);
  }
}
