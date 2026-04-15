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
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      unitCost: (json['unitCost'] as num?)?.toDouble() ?? 0.0,
      currentStock: (json['currentStock'] as num?)?.toInt() ?? 0,
      supplierId: json['supplierId'] as String?,
      manufacturerId: json['manufacturerId'] as String?,
      warehouseId: json['warehouseId'] as String?,
      isActive: json['isActive'] as bool? ?? true,
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
    };
  }
}
