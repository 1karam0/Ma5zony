class BomMaterial {
  final String rawMaterialId;
  final double quantityPerUnit;

  BomMaterial({
    required this.rawMaterialId,
    required this.quantityPerUnit,
  });

  factory BomMaterial.fromJson(Map<String, dynamic> json) {
    return BomMaterial(
      rawMaterialId: json['rawMaterialId'] as String,
      quantityPerUnit: (json['quantityPerUnit'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'rawMaterialId': rawMaterialId,
        'quantityPerUnit': quantityPerUnit,
      };
}

class BillOfMaterials {
  final String id;
  final String finalProductId;
  final List<BomMaterial> materials;

  BillOfMaterials({
    required this.id,
    required this.finalProductId,
    required this.materials,
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
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'finalProductId': finalProductId,
      'materials': materials.map((m) => m.toJson()).toList(),
    };
  }
}
