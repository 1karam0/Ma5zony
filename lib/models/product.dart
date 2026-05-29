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
  /// URL of the product's main/featured image, pulled from Shopify on import
  /// (`featuredImage.url`). Used to render a small thumbnail next to the
  /// product name in the products table.
  final String? imageUrl;
  /// Selling price charged to the customer (pulled from Shopify if available,
  /// or entered manually). Used for margin calculations.
  final double? sellingPrice;
  /// Extra per-unit production fee charged by the manufacturer on top of
  /// raw-material costs (only meaningful for manufactured products).
  final double? productionFee;
  /// Cost-per-item as last reported by Shopify (`inventoryItem.unitCost`).
  /// Kept separately from [unitCost] so we can detect when the user has
  /// overridden the Shopify value manually.
  final double? shopifyUnitCost;
  /// True when this product is a Shopify Bundle (composed of other variants).
  /// The effective cost is then derived from the sum of component costs.
  final bool isBundle;
  /// Components that make up this bundle. Empty for non-bundle products.
  final List<BundleComponent> bundleComponents;
  /// All sourcing options for this product. The first entry with
  /// [SourcingOption.isDefault] == true is the active option and drives cost,
  /// lead-time, and replenishment logic. Remaining entries are alternatives
  /// (backup suppliers, cheaper options, etc.).
  final List<SourcingOption> sourcingOptions;
  /// Per-warehouse stock breakdown. Keys are [Warehouse.id]; values are the
  /// on-hand unit count at that location. When non-empty, [currentStock]
  /// should equal the sum of all values. When empty, [currentStock] is the
  /// legacy single-location scalar.
  final Map<String, int> stockByWarehouse;

  /// Returns the stock count at a specific warehouse (0 if not tracked).
  int stockAtWarehouse(String warehouseId) =>
      stockByWarehouse[warehouseId] ?? 0;

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
    this.imageUrl,
    this.sellingPrice,
    this.productionFee,
    this.shopifyUnitCost,
    this.isBundle = false,
    this.bundleComponents = const [],
    this.sourcingOptions = const [],
    this.stockByWarehouse = const {},
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
    // Unit cost: must be set manually — never fall back to the Shopify selling price
    final unitCostRaw = _resolve<dynamic>(data, ['unitCost', 'unit_cost']);
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
      imageUrl: _resolve<String>(
          data, ['imageUrl', 'image_url', 'featuredImage', 'image']),
      // Selling price: app uses 'sellingPrice'; Shopify may carry it under
      // 'price' (we prefer 'sellingPrice' to avoid confusion with unitCost).
      sellingPrice: (data['sellingPrice'] as num?)?.toDouble() ??
          (_resolve<dynamic>(data, ['shopify_price', 'compareAtPrice']) as num?)
              ?.toDouble(),
      productionFee: (data['productionFee'] as num?)?.toDouble(),
      shopifyUnitCost: (data['shopifyUnitCost'] as num?)?.toDouble(),
      isBundle: data['isBundle'] as bool? ?? false,
      bundleComponents: (data['bundleComponents'] as List<dynamic>?)
              ?.map((e) => BundleComponent.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      sourcingOptions: (data['sourcingOptions'] as List<dynamic>?)
              ?.map((e) => SourcingOption.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      stockByWarehouse: {
        for (final entry in
            (data['stockByWarehouse'] as Map<String, dynamic>? ?? {}).entries)
          entry.key: (entry.value as num).toInt(),
      },
    );
  }

  /// Legacy JSON deserialization — also applies alias resolution for
  /// data that may have been written by Shopify Cloud Functions.
  factory Product.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    return Product.fromFirestore(id, json);
  }

  /// Returns a copy with the given fields overridden. Nullable fields use a
  /// sentinel pattern is avoided for simplicity — pass the existing value to
  /// keep it. Used by bulk-edit flows (e.g. assigning a supplier to many
  /// imported products at once).
  Product copyWith({
    String? id,
    String? sku,
    String? name,
    String? category,
    double? unitCost,
    int? currentStock,
    String? supplierId,
    String? manufacturerId,
    String? warehouseId,
    bool? isActive,
    int? leadTimeDays,
    double? averageDailySales,
    int? minimumStock,
    String? shopifyVariantId,
    String? shopifyProductId,
    String? imageUrl,
    double? sellingPrice,
    double? productionFee,
    double? shopifyUnitCost,
    bool? isBundle,
    List<BundleComponent>? bundleComponents,
    List<SourcingOption>? sourcingOptions,
    Map<String, int>? stockByWarehouse,
  }) {
    return Product(
      id: id ?? this.id,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      category: category ?? this.category,
      unitCost: unitCost ?? this.unitCost,
      currentStock: currentStock ?? this.currentStock,
      supplierId: supplierId ?? this.supplierId,
      manufacturerId: manufacturerId ?? this.manufacturerId,
      warehouseId: warehouseId ?? this.warehouseId,
      isActive: isActive ?? this.isActive,
      leadTimeDays: leadTimeDays ?? this.leadTimeDays,
      averageDailySales: averageDailySales ?? this.averageDailySales,
      minimumStock: minimumStock ?? this.minimumStock,
      shopifyVariantId: shopifyVariantId ?? this.shopifyVariantId,
      shopifyProductId: shopifyProductId ?? this.shopifyProductId,
      imageUrl: imageUrl ?? this.imageUrl,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      productionFee: productionFee ?? this.productionFee,
      shopifyUnitCost: shopifyUnitCost ?? this.shopifyUnitCost,
      isBundle: isBundle ?? this.isBundle,
      bundleComponents: bundleComponents ?? this.bundleComponents,
      sourcingOptions: sourcingOptions ?? this.sourcingOptions,
      stockByWarehouse: stockByWarehouse ?? this.stockByWarehouse,
    );
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
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (sellingPrice != null) 'sellingPrice': sellingPrice,
      if (productionFee != null) 'productionFee': productionFee,
      if (shopifyUnitCost != null) 'shopifyUnitCost': shopifyUnitCost,
      if (isBundle) 'isBundle': true,
      if (bundleComponents.isNotEmpty)
        'bundleComponents':
            bundleComponents.map((c) => c.toJson()).toList(),
      if (sourcingOptions.isNotEmpty)
        'sourcingOptions': sourcingOptions.map((o) => o.toJson()).toList(),
      if (stockByWarehouse.isNotEmpty)
        'stockByWarehouse': stockByWarehouse,
    };
  }
}

/// One way to source a product — either by purchasing from a supplier or
/// by having it manufactured. A product can have multiple options; the one
/// with [isDefault] = true drives cost calculations and replenishment orders.
class SourcingOption {
  /// 'purchase' — buy from a supplier; 'manufacture' — make with a manufacturer.
  final String kind;
  final String? supplierId;
  final String? manufacturerId;
  /// Unit cost for this sourcing path (for manufacture options, this reflects
  /// BOM material cost + production fee at save time).
  final double unitCost;
  /// Typical days from order placement to stock receipt.
  final int leadTimeDays;
  /// Minimum order quantity for this option (null = no minimum).
  final int? moq;
  /// Whether this is the active/primary sourcing path.
  final bool isDefault;

  const SourcingOption({
    required this.kind,
    this.supplierId,
    this.manufacturerId,
    required this.unitCost,
    required this.leadTimeDays,
    this.moq,
    this.isDefault = false,
  });

  factory SourcingOption.fromJson(Map<String, dynamic> json) {
    return SourcingOption(
      kind: json['kind'] as String? ?? 'purchase',
      supplierId: json['supplierId'] as String?,
      manufacturerId: json['manufacturerId'] as String?,
      unitCost: (json['unitCost'] as num?)?.toDouble() ?? 0.0,
      leadTimeDays: (json['leadTimeDays'] as num?)?.toInt() ?? 0,
      moq: (json['moq'] as num?)?.toInt(),
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (supplierId != null) 'supplierId': supplierId,
        if (manufacturerId != null) 'manufacturerId': manufacturerId,
        'unitCost': unitCost,
        'leadTimeDays': leadTimeDays,
        if (moq != null) 'moq': moq,
        'isDefault': isDefault,
      };
}

/// A single line in a bundle: how many of which component variant this
/// bundle contains. Either [productId] (Ma5zony Firestore id) or
/// [shopifyVariantId] / [shopifyProductId] can be used to look up the
/// component's current unit cost when computing the bundle's effective cost.
class BundleComponent {
  /// Ma5zony product id of the component (resolved post-import when possible).
  final String? productId;
  /// Shopify variant id of the component (raw numeric id, no `gid://` prefix).
  final String? shopifyVariantId;
  /// Shopify parent product id of the component.
  final String? shopifyProductId;
  /// Quantity of this component contained in one bundle unit.
  final int quantity;
  /// Display name of the component variant (for UI; not used in cost calc).
  final String? name;

  const BundleComponent({
    this.productId,
    this.shopifyVariantId,
    this.shopifyProductId,
    required this.quantity,
    this.name,
  });

  factory BundleComponent.fromJson(Map<String, dynamic> json) {
    return BundleComponent(
      productId: json['productId'] as String?,
      shopifyVariantId: json['shopifyVariantId']?.toString(),
      shopifyProductId: json['shopifyProductId']?.toString(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (productId != null) 'productId': productId,
        if (shopifyVariantId != null) 'shopifyVariantId': shopifyVariantId,
        if (shopifyProductId != null) 'shopifyProductId': shopifyProductId,
        'quantity': quantity,
        if (name != null) 'name': name,
      };
}
