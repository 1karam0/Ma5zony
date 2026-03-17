class Supplier {
  final String id;
  final String name;
  final String contactEmail;
  final String? phone;
  final int typicalLeadTimeDays;

  Supplier({
    required this.id,
    required this.name,
    required this.contactEmail,
    this.phone,
    required this.typicalLeadTimeDays,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'] as String,
      name: json['name'] as String,
      contactEmail: json['contactEmail'] as String,
      phone: json['phone'] as String?,
      typicalLeadTimeDays: (json['typicalLeadTimeDays'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'contactEmail': contactEmail,
      'phone': phone,
      'typicalLeadTimeDays': typicalLeadTimeDays,
    };
  }
}
