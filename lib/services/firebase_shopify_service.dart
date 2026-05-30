import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/shopify_store_connection.dart';
import 'package:ma5zony/services/shopify_integration_service.dart';
import 'package:ma5zony/utils/cloud_function_config.dart';

/// Real Shopify integration service that calls Firebase Cloud Functions
/// via direct HTTP (avoids the cloud_functions SDK Int64 dart2js bug).
///
/// OAuth tokens are stored server-side only — the Flutter client never
/// handles Shopify access tokens directly.
class FirebaseShopifyService implements ShopifyIntegrationService {
  final String uid;
  final FirebaseFirestore _firestore;

  FirebaseShopifyService({required this.uid})
      : _firestore = FirebaseFirestore.instance;

  DocumentReference get _connectionDoc =>
      _firestore.collection('users').doc(uid).collection('shopify').doc('connection');

  static final Map<String, String Function()> _functionUrls = {
    'shopifyGetOAuthUrl': () => CloudFunctionConfig.shopifyGetOAuthUrl,
    'shopifyOAuthCallback': () => CloudFunctionConfig.shopifyOAuthCallback,
    'shopifyImportProducts': () => CloudFunctionConfig.shopifyImportProducts,
    'shopifySyncStock': () => CloudFunctionConfig.shopifySyncStock,
    'shopifyDisconnectStore': () => CloudFunctionConfig.shopifyDisconnectStore,
    'shopifyImportOrders': () => CloudFunctionConfig.shopifyImportOrders,
  };

  /// Calls a callable Cloud Function via HTTP POST with Firebase Auth token.
  Future<Map<String, dynamic>> _callFunction(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();

    final urlBuilder = _functionUrls[name];
    if (urlBuilder == null) throw Exception('Unknown function: $name');
    final url = urlBuilder();

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'data': data ?? {}}),
    );

    if (response.statusCode != 200) {
      final body = response.body;
      throw Exception('Cloud Function $name failed (${response.statusCode}): $body');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    // Callable functions wrap the response in {"result": ...}
    return (decoded['result'] as Map<String, dynamic>?) ?? decoded;
  }

  // ── Connection state ───────────────────────────────────────────────────────

  @override
  Future<ShopifyStoreConnection> getCurrentConnection() async {
    final snap = await _connectionDoc.get();
    if (!snap.exists) {
      return ShopifyStoreConnection(
        id: 'shopify_conn',
        shopDomain: '',
        isConnected: false,
      );
    }
    final data = snap.data() as Map<String, dynamic>;
    return ShopifyStoreConnection(
      id: snap.id,
      shopDomain: data['shopDomain'] as String? ?? '',
      isConnected: data['isConnected'] as bool? ?? false,
      lastSyncAt: data['lastSyncAt'] != null
          ? (data['lastSyncAt'] as Timestamp).toDate()
          : null,
    );
  }

  // ── OAuth flow ─────────────────────────────────────────────────────────────

  /// Calls the Cloud Function `shopifyGetOAuthUrl` and returns the
  /// authorization URL that the caller should open in a browser.
  Future<String> getOAuthUrl(String shopDomain) async {
    final result = await _callFunction(
      'shopifyGetOAuthUrl',
      {'shopDomain': shopDomain},
    );
    return result['authUrl'] as String;
  }

  @override
  Future<ShopifyStoreConnection> connectStore({
    required String shopDomain,
  }) async {
    // Listen to the connection document via Firestore snapshots instead of
    // polling. Resolves as soon as the OAuth callback writes isConnected=true.
    final completer = Completer<ShopifyStoreConnection>();
    final sub = _connectionDoc.snapshots().listen((snap) {
      if (completer.isCompleted) return;
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>?;
      if (data == null) return;
      if (data['isConnected'] == true) {
        completer.complete(ShopifyStoreConnection(
          id: snap.id,
          shopDomain: data['shopDomain'] as String? ?? shopDomain,
          isConnected: true,
          lastSyncAt: data['lastSyncAt'] != null
              ? (data['lastSyncAt'] as Timestamp).toDate()
              : null,
        ));
      }
    });

    try {
      // Wait up to 120 seconds for the OAuth flow to complete.
      return await completer.future.timeout(
        const Duration(seconds: 120),
        onTimeout: () => getCurrentConnection(),
      );
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<void> disconnectStore() async {
    await _callFunction('shopifyDisconnectStore');
  }

  // ── Import / Sync ──────────────────────────────────────────────────────────

  /// Parses the product list returned by the shopifyImportProducts function.
  static List<Product> _parseProductList(Map<String, dynamic> result) {
    final raw = (result['products'] as List?) ?? [];
    return raw.map((p) {
      final m = Map<String, dynamic>.from(p as Map);
      return Product(
        id: m['id'] as String? ?? '',
        sku: m['sku'] as String? ?? '',
        name: m['name'] as String? ?? '',
        category: m['category'] as String? ?? 'Uncategorised',
        unitCost: (m['unitCost'] as num?)?.toDouble() ?? 0,
        currentStock: (m['currentStock'] as num?)?.toInt() ?? 0,
        supplierId: m['supplierId'] as String?,
        isActive: m['isActive'] as bool? ?? true,
        imageUrl: m['imageUrl'] as String?,
        sellingPrice: (m['sellingPrice'] as num?)?.toDouble(),
        shopifyProductId: m['shopifyProductId'] as String?,
        shopifyVariantId: m['shopifyVariantId'] as String?,
        variants: (m['variants'] as List?)
                ?.map((e) =>
                    ProductVariant.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
      );
    }).toList();
  }

  @override
  Future<List<Product>> importProductsFromShopify() async {
    final result = await _callFunction('shopifyImportProducts');
    return _parseProductList(result);
  }

  @override
  Future<void> syncInventoryFromShopify() async {
    await _callFunction('shopifySyncStock');
  }

  /// Returns a list of products available in Shopify **without** writing them
  /// to Firestore. Used by the picker dialog for a safe preview.
  Future<List<Product>> fetchShopifyProducts() async {
    final conn = await getCurrentConnection();
    if (!conn.isConnected) return [];
    final result = await _callFunction(
      'shopifyImportProducts',
      {'previewOnly': true},
    );
    return _parseProductList(result);
  }

  /// Imports **only** the specified products (by Firestore doc ID, e.g.
  /// "shopify_123") to Firestore. All other products are left untouched.
  Future<List<Product>> importSelectedFromShopify(List<String> docIds) async {
    final result = await _callFunction(
      'shopifyImportProducts',
      {'selectedShopifyIds': docIds},
    );
    return _parseProductList(result);
  }

  /// Imports Shopify order history and converts line items into demand records.
  /// Returns the count of newly imported demand records.
  Future<Map<String, dynamic>> importOrderHistory() async {
    return _callFunction('shopifyImportOrders');
  }
}
