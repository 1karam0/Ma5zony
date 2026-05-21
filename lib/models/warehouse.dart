class Warehouse {
  final String id;
  final String name;
  final String city;
  final String country;
  final String? address;
  final double? latitude;
  final double? longitude;
  int totalStock;

  Warehouse({
    required this.id,
    required this.name,
    required this.city,
    required this.country,
    this.address,
    this.latitude,
    this.longitude,
    this.totalStock = 0,
  });

  factory Warehouse.fromJson(Map<String, dynamic> json) {
    return Warehouse(
      id: json['id'] as String,
      name: json['name'] as String,
      city: json['city'] as String? ?? '',
      country: json['country'] as String? ?? '',
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      totalStock: (json['totalStock'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'city': city,
      'country': country,
      if (address != null) 'address': address,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'totalStock': totalStock,
    };
  }
}
