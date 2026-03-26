/// Application-level user profile backed by Firestore `users/{uid}`.
class AppUser {
  final String uid;
  final String name;
  final String email;
  final String role; // 'SME Owner', 'Inventory Manager'
  /// For Inventory Managers: the uid of the SME Owner they belong to.
  final String? ownerId;

  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.ownerId,
  });

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
