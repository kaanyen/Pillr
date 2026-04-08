import 'package:cloud_firestore/cloud_firestore.dart';

class ChurchUser {
  ChurchUser({
    required this.uid,
    required this.churchId,
    required this.role,
    required this.fullName,
    required this.email,
    this.phone,
    this.avatarUrl,
    required this.isActive,
    this.lastLoginAt,
  });

  final String uid;
  final String churchId;
  final String role;
  final String fullName;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final bool isActive;
  final DateTime? lastLoginAt;

  static ChurchUser? fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    return ChurchUser(
      uid: data['uid'] as String? ?? doc.id,
      churchId: data['churchId'] as String? ?? '',
      role: data['role'] as String? ?? 'staff',
      fullName: data['fullName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String?,
      avatarUrl: data['avatarUrl'] as String?,
      isActive: data['isActive'] as bool? ?? true,
      lastLoginAt: data['lastLoginAt'] != null
          ? (data['lastLoginAt'] as Timestamp).toDate()
          : null,
    );
  }
}
