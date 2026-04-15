/// UI-only model representing a Shopify store connection.
/// Real OAuth tokens MUST be stored server-side, never in Flutter.
class ShopifyStoreConnection {
  final String id;
  final String shopDomain; // e.g. "mystore.myshopify.com"
  bool isConnected;
  DateTime? lastSyncAt;

  ShopifyStoreConnection({
    required this.id,
    required this.shopDomain,
    this.isConnected = false,
    this.lastSyncAt,
  });

  factory ShopifyStoreConnection.fromJson(Map<String, dynamic> json) {
    return ShopifyStoreConnection(
      id: json['id'] as String? ?? '',
      shopDomain: json['shopDomain'] as String? ?? '',
      isConnected: json['isConnected'] as bool? ?? false,
      lastSyncAt: json['lastSyncAt'] != null
          ? DateTime.parse(json['lastSyncAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shopDomain': shopDomain,
      'isConnected': isConnected,
      'lastSyncAt': lastSyncAt?.toIso8601String(),
    };
  }
}
