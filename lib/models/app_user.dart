/// Application-level user profile backed by Firestore `users/{uid}`.
class AppUser {
  static const String roleSmeOwner = 'SME Owner';
  static const String roleInventoryManager = 'Inventory Manager';
  static const String roleManufacturer = 'Manufacturer';
  static const String roleRawMaterialFactory = 'Raw Material Factory';

  static const List<String> allRoles = [
    roleSmeOwner,
    roleInventoryManager,
    roleManufacturer,
    roleRawMaterialFactory,
  ];

  final String uid;
  final String name;
  final String email;
  final String role;
  /// For non-owner roles: the uid of the SME Owner they belong to.
  final String? ownerId;

  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.ownerId,
  });

  bool get isSmeOwner => role == roleSmeOwner;
  bool get isInventoryManager => role == roleInventoryManager;
  bool get isManufacturer => role == roleManufacturer;
  bool get isRawMaterialFactory => role == roleRawMaterialFactory;

  factory AppUser.fromFirestore(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? 'Inventory Manager',
      ownerId: data['ownerId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'role': role,
      if (ownerId != null) 'ownerId': ownerId,
    };
  }
}
