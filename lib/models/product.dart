class Product {
  final String id;
  final String sku;
  final String name;
  final String category;
  final double unitCost;
  int currentStock;
  final String? supplierId;
  final String? manufacturerId;
  final String? warehouseId;
  final bool isActive;
  final int leadTimeDays;
  final double? averageDailySales;
  final int? minimumStock;
  final String? shopifyVariantId;
  final String? shopifyProductId;

  Product({
    required this.id,
    required this.sku,
    required this.name,
    required this.category,
    required this.unitCost,
    this.currentStock = 0,
    this.supplierId,
    this.manufacturerId,
    this.warehouseId,
    this.isActive = true,
    this.leadTimeDays = 0,
    this.averageDailySales,
    this.minimumStock,
    this.shopifyVariantId,
    this.shopifyProductId,
  });

  /// Resolves a value from multiple possible field name aliases.
  /// Used to handle Shopify-imported docs vs manually-created docs.
  static T? _resolve<T>(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      if (data.containsKey(k) && data[k] != null) return data[k] as T?;
    }
    return null;
  }

  /// Primary deserialization for Firestore documents.
  /// Handles both app-native field names and Shopify-imported field names.
  factory Product.fromFirestore(String id, Map<String, dynamic> data) {
    // SKU: app uses 'sku'; Shopify may use 'variant_sku' or 'SKU'
    final sku = _resolve<String>(data, ['sku', 'variant_sku', 'SKU']) ?? '';
    // Name: app uses 'name'; Shopify uses 'title'
    final name = _resolve<String>(data, ['name', 'title', 'productName']) ?? '';
    // Category: app uses 'category'; Shopify uses 'product_type' or 'type'
    final category =
        _resolve<String>(data, ['category', 'product_type', 'type']) ??
            'Uncategorised';
    // Unit cost: app uses 'unitCost'; Shopify uses 'price' or 'unit_cost'
    final unitCostRaw =
        _resolve<dynamic>(data, ['unitCost', 'unit_cost', 'price']);
    final unitCost = (unitCostRaw as num?)?.toDouble() ?? 0.0;
    // Stock: app uses 'currentStock'; Shopify uses 'inventory_quantity'
    final stockRaw =
        _resolve<dynamic>(data, ['currentStock', 'inventory_quantity', 'stock']);
    final currentStock = (stockRaw as num?)?.toInt() ?? 0;

    return Product(
      id: id,
      sku: sku.isNotEmpty ? sku : id.substring(0, 8), // fallback to truncated ID
      name: name,
      category: category,
      unitCost: unitCost,
      currentStock: currentStock,
      supplierId: data['supplierId'] as String?,
      manufacturerId: data['manufacturerId'] as String?,
      warehouseId: data['warehouseId'] as String?,
      isActive: data['isActive'] as bool? ?? true,
      leadTimeDays: (data['leadTimeDays'] as num?)?.toInt() ?? 0,
      averageDailySales:
          (data['averageDailySales'] as num?)?.toDouble(),
      minimumStock: (data['minimumStock'] as num?)?.toInt(),
      shopifyVariantId: data['shopifyVariantId'] as String?,
      shopifyProductId: _resolve<String>(
              data, ['shopifyProductId', 'shopify_product_id'])
          ?.toString(),
    );
  }

  /// Legacy JSON deserialization — also applies alias resolution for
  /// data that may have been written by Shopify Cloud Functions.
  factory Product.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    return Product.fromFirestore(id, json);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sku': sku,
      'name': name,
      'category': category,
      'unitCost': unitCost,
      'currentStock': currentStock,
      'supplierId': supplierId,
      'manufacturerId': manufacturerId,
      'warehouseId': warehouseId,
      'isActive': isActive,
      'leadTimeDays': leadTimeDays,
      if (averageDailySales != null) 'averageDailySales': averageDailySales,
      if (minimumStock != null) 'minimumStock': minimumStock,
      if (shopifyVariantId != null) 'shopifyVariantId': shopifyVariantId,
      if (shopifyProductId != null) 'shopifyProductId': shopifyProductId,
    };
  }
}
