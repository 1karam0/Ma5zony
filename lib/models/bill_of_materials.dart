class BomMaterial {
  final String rawMaterialId;
  final double quantityPerUnit;
  final String unitOfMeasure;

  BomMaterial({
    required this.rawMaterialId,
    required this.quantityPerUnit,
    this.unitOfMeasure = 'units',
  });

  factory BomMaterial.fromJson(Map<String, dynamic> json) {
    return BomMaterial(
      rawMaterialId: json['rawMaterialId'] as String,
      quantityPerUnit: (json['quantityPerUnit'] as num).toDouble(),
      unitOfMeasure: json['unitOfMeasure'] as String? ?? 'units',
    );
  }

  Map<String, dynamic> toJson() => {
        'rawMaterialId': rawMaterialId,
        'quantityPerUnit': quantityPerUnit,
        'unitOfMeasure': unitOfMeasure,
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
