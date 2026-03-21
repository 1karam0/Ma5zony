import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/shopify_store_connection.dart';

/// Abstract gateway for Shopify integration.
///
/// SECURITY NOTE: Real API tokens and OAuth credentials MUST be stored and
/// managed on a backend server. Flutter clients should never hold Shopify
/// access tokens. Calls from Flutter go to YOUR backend, which proxies to
/// Shopify's API.
abstract class ShopifyIntegrationService {
  Future<ShopifyStoreConnection> getCurrentConnection();

  /// Connects to the given [shopDomain] via OAuth.
  Future<ShopifyStoreConnection> connectStore({required String shopDomain});

  Future<void> disconnectStore();

  /// Returns products imported from Shopify.
  Future<List<Product>> importProductsFromShopify();

  /// Syncs current inventory levels from Shopify.
  Future<void> syncInventoryFromShopify();
}
