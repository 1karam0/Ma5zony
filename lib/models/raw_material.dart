class RawMaterial {
  final String id;
  final String name;
  final String sku;
  final String unit;
  final String unitOfMeasure;
  final double unitCost;
  final String? supplierId;
  int currentStock;
  int safetyStock;
  final int leadTimeDays;

  /// When true (default), [safetyStock] is treated as an automatically
  /// computed reorder point — the system recalculates it from product demand
  /// exploded through the BOM plus this material's lead time. When false, the
  /// user has manually overridden the reorder level and the system leaves it
  /// untouched.
  bool autoSafetyStock;

  RawMaterial({
    required this.id,
    required this.name,
    required this.sku,
    required this.unit,
    String? unitOfMeasure,
    required this.unitCost,
    this.supplierId,
    this.currentStock = 0,
    this.safetyStock = 0,
    this.leadTimeDays = 0,
    this.autoSafetyStock = true,
  }) : unitOfMeasure = unitOfMeasure ?? unit;

  factory RawMaterial.fromFirestore(String id, Map<String, dynamic> data) {
    final unit = data['unit'] as String? ?? 'pcs';
    return RawMaterial(
      id: id,
      name: data['name'] as String? ?? '',
      sku: data['sku'] as String? ?? '',
      unit: unit,
      unitOfMeasure: data['unitOfMeasure'] as String? ?? unit,
      unitCost: (data['unitCost'] as num?)?.toDouble() ?? 0,
      supplierId: data['supplierId'] as String?,
      currentStock: (data['currentStock'] as num?)?.toInt() ?? 0,
      safetyStock: (data['safetyStock'] as num?)?.toInt() ?? 0,
      leadTimeDays: (data['leadTimeDays'] as num?)?.toInt() ?? 0,
      autoSafetyStock: data['autoSafetyStock'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'sku': sku,
      'unit': unit,
      'unitOfMeasure': unitOfMeasure,
      'unitCost': unitCost,
      if (supplierId != null) 'supplierId': supplierId,
      'currentStock': currentStock,
      'safetyStock': safetyStock,
      'leadTimeDays': leadTimeDays,
      'autoSafetyStock': autoSafetyStock,
    };
  }
}
