import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/shopify_store_connection.dart';
import 'package:ma5zony/services/mock_inventory_repository.dart';

/// Abstract gateway for Shopify integration.
///
/// SECURITY NOTE: Real API tokens and OAuth credentials MUST be stored and
/// managed on a backend server. Flutter clients should never hold Shopify
/// access tokens. Calls from Flutter go to YOUR backend, which proxies to
/// Shopify's API.
abstract class ShopifyIntegrationService {
  Future<ShopifyStoreConnection> getCurrentConnection();

  /// Initiates a (mock) connection to [shopDomain].
  Future<ShopifyStoreConnection> connectStore({required String shopDomain});

  Future<void> disconnectStore();

  /// Returns products imported from Shopify (stub: returns demo data).
  Future<List<Product>> importProductsFromShopify();

  /// Syncs current inventory levels from Shopify (stub: no-op).
  Future<void> syncInventoryFromShopify();
}

// ─────────────────────────────────────────────────────────────────────────────

/// Stub implementation — purely in-memory, no real HTTP calls.
/// Swap this for a real class that calls your backend when ready.
class MockShopifyIntegrationService implements ShopifyIntegrationService {
  final MockInventoryRepository _repository;

  ShopifyStoreConnection _connection = ShopifyStoreConnection(
    id: 'shopify_conn_1',
    shopDomain: '',
    isConnected: false,
  );

  MockShopifyIntegrationService({required MockInventoryRepository repository})
    : _repository = repository;

  @override
  Future<ShopifyStoreConnection> getCurrentConnection() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _connection;
  }

  @override
  Future<ShopifyStoreConnection> connectStore({
    required String shopDomain,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _connection = ShopifyStoreConnection(
      id: _connection.id,
      shopDomain: shopDomain,
      isConnected: true,
      lastSyncAt: DateTime.now(),
    );
    return _connection;
  }

  @override
  Future<void> disconnectStore() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _connection = ShopifyStoreConnection(
      id: _connection.id,
      shopDomain: _connection.shopDomain,
      isConnected: false,
    );
  }

  @override
  Future<List<Product>> importProductsFromShopify() async {
    await Future.delayed(const Duration(milliseconds: 800));
    final imported = [
      Product(
        id: 'sp1',
        sku: 'SH-001',
        name: 'Shopify T-Shirt',
        category: 'Apparel',
        unitCost: 15.0,
        currentStock: 100,
        supplierId: 's1',
        isActive: true,
      ),
      Product(
        id: 'sp2',
        sku: 'SH-002',
        name: 'Shopify Mug',
        category: 'Accessories',
        unitCost: 5.0,
        currentStock: 50,
        supplierId: 's1',
        isActive: true,
      ),
    ];
    _repository.mergeProducts(imported);
    return imported;
  }

  @override
  Future<void> syncInventoryFromShopify() async {
    // Stub: simulate a sync delay.
    // Real implementation would call your backend to fetch Shopify inventory
    // levels and update [_repository] accordingly.
    await Future.delayed(const Duration(seconds: 1));
    _connection = ShopifyStoreConnection(
      id: _connection.id,
      shopDomain: _connection.shopDomain,
      isConnected: _connection.isConnected,
      lastSyncAt: DateTime.now(),
    );
  }
}
