class Manufacturer {
  final String id;
  final String name;
  final String contactEmail;
  final String? phone;
  final int productionCapacity;
  final int typicalProductionDays;

  Manufacturer({
    required this.id,
    required this.name,
    required this.contactEmail,
    this.phone,
    required this.productionCapacity,
    required this.typicalProductionDays,
  });

  factory Manufacturer.fromFirestore(String id, Map<String, dynamic> data) {
    return Manufacturer(
      id: id,
      name: data['name'] as String? ?? '',
      contactEmail: data['contactEmail'] as String? ?? '',
      phone: data['phone'] as String?,
      productionCapacity: (data['productionCapacity'] as num?)?.toInt() ?? 0,
      typicalProductionDays:
          (data['typicalProductionDays'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'contactEmail': contactEmail,
      'phone': phone,
      'productionCapacity': productionCapacity,
      'typicalProductionDays': typicalProductionDays,
    };
  }
}
