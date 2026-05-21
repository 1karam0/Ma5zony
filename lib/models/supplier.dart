class Supplier {
  final String id;
  final String name;
  final String contactEmail;
  final String? phone;
  final int typicalLeadTimeDays;
  /// On-time delivery / quality rating, 0.0 – 5.0. Null = not rated yet.
  final double? performanceRating;
  final String? address;
  final double? latitude;
  final double? longitude;

  Supplier({
    required this.id,
    required this.name,
    required this.contactEmail,
    this.phone,
    required this.typicalLeadTimeDays,
    this.performanceRating,
    this.address,
    this.latitude,
    this.longitude,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'] as String,
      name: json['name'] as String,
      contactEmail: json['contactEmail'] as String,
      phone: json['phone'] as String?,
      typicalLeadTimeDays: (json['typicalLeadTimeDays'] as num).toInt(),
      performanceRating: json['performanceRating'] != null
          ? (json['performanceRating'] as num).toDouble()
          : null,
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'contactEmail': contactEmail,
      'phone': phone,
      'typicalLeadTimeDays': typicalLeadTimeDays,
      if (performanceRating != null) 'performanceRating': performanceRating,
      if (address != null) 'address': address,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };
  }
}
