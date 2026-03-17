class Warehouse {
  final String id;
  final String name;
  final String city;
  final String country;
  int totalStock;

  Warehouse({
    required this.id,
    required this.name,
    required this.city,
    required this.country,
    this.totalStock = 0,
  });

  factory Warehouse.fromJson(Map<String, dynamic> json) {
    return Warehouse(
      id: json['id'] as String,
      name: json['name'] as String,
      city: json['city'] as String,
      country: json['country'] as String,
      totalStock: (json['totalStock'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'city': city,
      'country': country,
      'totalStock': totalStock,
    };
  }
}
