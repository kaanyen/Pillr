import 'package:cloud_firestore/cloud_firestore.dart';

class UserChurchIndex {
  UserChurchIndex({
    required this.uid,
    required this.churchId,
    required this.role,
  });

  final String uid;
  final String churchId;
  final String role; // admin | pastor | staff

  bool get isAdmin => role == 'admin';
  bool get isPastor => role == 'pastor';
  bool get isStaff => role == 'staff';

  /// Pastor, church admin, or staff — create, rename, merge, dissolve, move.
  bool get canManageFellowships => isPastor || isAdmin || isStaff;

  /// Ledger repairs on Tools: totals, merge duplicates, void duplicate
  /// entries, tidy names. Writes go to the activity log.
  bool get canUseTools => isPastor || isAdmin || isStaff;

  /// Set USD/EUR/GBP → GHS rates. Recalculating saved entries stays pastor-only.
  bool get canEditExchangeRates => isPastor || isAdmin || isStaff;

  static UserChurchIndex? fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final churchId = data['churchId'] as String?;
    final role = data['role'] as String?;
    if (churchId == null || role == null) return null;
    return UserChurchIndex(uid: doc.id, churchId: churchId, role: role);
  }
}
