class RawMaterial {
  final String id;
  final String name;
  final String sku;
  final String unit;
  final double unitCost;
  final String supplierId;
  int currentStock;
  final int safetyStock;

  RawMaterial({
    required this.id,
    required this.name,
    required this.sku,
    required this.unit,
    required this.unitCost,
    required this.supplierId,
    this.currentStock = 0,
    this.safetyStock = 0,
  });

  factory RawMaterial.fromFirestore(String id, Map<String, dynamic> data) {
    return RawMaterial(
      id: id,
      name: data['name'] as String? ?? '',
      sku: data['sku'] as String? ?? '',
      unit: data['unit'] as String? ?? 'pcs',
      unitCost: (data['unitCost'] as num?)?.toDouble() ?? 0,
      supplierId: data['supplierId'] as String? ?? '',
      currentStock: (data['currentStock'] as num?)?.toInt() ?? 0,
      safetyStock: (data['safetyStock'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'sku': sku,
      'unit': unit,
      'unitCost': unitCost,
      'supplierId': supplierId,
      'currentStock': currentStock,
      'safetyStock': safetyStock,
    };
  }
}
