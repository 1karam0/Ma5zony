/// What a BOM line points at. Defaults to a raw material so any legacy
/// document (which only stored `rawMaterialId`) keeps reading correctly.
///
/// - [rawMaterial] — leaf input, looked up in the `rawMaterials` collection.
/// - [product]     — a sub-assembly / intermediate product whose own BOM
///                   should be rolled up recursively for cost.
enum BomComponentKind { rawMaterial, product }

class BomMaterial {
  /// Legacy field — kept for backwards compatibility. When [kind] is
  /// [BomComponentKind.rawMaterial] this is the raw-material id; when
  /// [kind] is [BomComponentKind.product] this is the sub-product id.
  /// Prefer reading [refId] below.
  final String rawMaterialId;
  final double quantityPerUnit;
  final String unitOfMeasure;

  /// Whether the referenced id is a raw material or a finished/intermediate
  /// product. Defaults to raw material so existing docs migrate silently.
  final BomComponentKind kind;

  /// Optional process yield. If 100g of input produces 85g of output, the
  /// quantity actually consumed per unit of finished good is
  /// `quantityPerUnit / (yieldPercent / 100)`. `null` and `100` are
  /// equivalent (no loss). Range is enforced 1..100 at read time.
  final double? yieldPercent;

  /// Optional Shopify variant id this line applies to. When `null` the line
  /// is **shared** — consumed by every variant of the finished product. When
  /// set, the material is only consumed when building that specific variant
  /// (e.g. "red strap" → only the Red variant of Figure-8 Straps).
  final String? variantId;

  BomMaterial({
    required this.rawMaterialId,
    required this.quantityPerUnit,
    this.unitOfMeasure = 'units',
    this.kind = BomComponentKind.rawMaterial,
    this.yieldPercent,
    this.variantId,
  });

  /// Unified accessor: the id of whatever this line points at.
  String get refId => rawMaterialId;

  /// Effective consumption per unit of finished good once yield loss is
  /// applied. A 15% loss on a 1kg recipe consumes 1 / 0.85 = 1.176 kg.
  double get effectiveQuantityPerUnit {
    final y = yieldPercent;
    if (y == null || y >= 100 || y <= 0) return quantityPerUnit;
    return quantityPerUnit / (y / 100.0);
  }

  factory BomMaterial.fromJson(Map<String, dynamic> json) {
    final kindStr = json['kind'] as String?;
    final kind = kindStr == 'product'
        ? BomComponentKind.product
        : BomComponentKind.rawMaterial;
    // Accept either the new generic `refId` or the legacy `rawMaterialId`.
    final ref = (json['refId'] as String?) ??
        (json['rawMaterialId'] as String? ?? '');
    final yp = (json['yieldPercent'] as num?)?.toDouble();
    return BomMaterial(
      rawMaterialId: ref,
      quantityPerUnit: (json['quantityPerUnit'] as num).toDouble(),
      unitOfMeasure: json['unitOfMeasure'] as String? ?? 'units',
      kind: kind,
      yieldPercent: (yp != null && yp > 0 && yp <= 100) ? yp : null,
      variantId: (json['variantId'] as String?)?.isNotEmpty == true
          ? json['variantId'] as String?
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        // Keep `rawMaterialId` populated so any older reader (or rule check)
        // continues to work. `refId` is the canonical write field.
        'rawMaterialId': rawMaterialId,
        'refId': rawMaterialId,
        'kind': kind == BomComponentKind.product ? 'product' : 'rawMaterial',
        'quantityPerUnit': quantityPerUnit,
        'unitOfMeasure': unitOfMeasure,
        if (yieldPercent != null) 'yieldPercent': yieldPercent,
        if (variantId != null) 'variantId': variantId,
      };
}

class BillOfMaterials {
  final String id;
  final String finalProductId;
  final List<BomMaterial> materials;
  final bool isActive;

  BillOfMaterials({
    required this.id,
    required this.finalProductId,
    required this.materials,
    this.isActive = true,
  });

  factory BillOfMaterials.fromFirestore(String id, Map<String, dynamic> data) {
    final materialsList = (data['materials'] as List<dynamic>?)
            ?.map((e) => BomMaterial.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return BillOfMaterials(
      id: id,
      finalProductId: data['finalProductId'] as String? ?? '',
      materials: materialsList,
      isActive: data['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'finalProductId': finalProductId,
      'materials': materials.map((m) => m.toJson()).toList(),
      'isActive': isActive,
    };
  }
}
