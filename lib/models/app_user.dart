/// Application-level user profile backed by Firestore `users/{uid}`.
class AppUser {
  final String uid;
  final String name;
  final String email;
  final String role; // 'SME Owner', 'Inventory Manager'

  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
  });

  factory AppUser.fromFirestore(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? 'Inventory Manager',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'role': role,
    };
  }
}
