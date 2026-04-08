import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/church_settings.dart';

class ChurchSettingsRepository {
  ChurchSettingsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _church(String churchId) {
    return _firestore.collection('churches').doc(churchId);
  }

  Stream<ChurchSettings?> watchChurch(String churchId) {
    return _church(churchId).snapshots().map(ChurchSettings.fromSnapshot);
  }

  Future<void> updateBranding({
    required String churchId,
    String? name,
    String? primaryColorHex,
    String? logoUrl,
    String? logoStoragePath,
  }) async {
    final map = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) map['name'] = name.trim();
    if (primaryColorHex != null) map['primaryColorHex'] = primaryColorHex;
    if (logoUrl != null) map['logoUrl'] = logoUrl;
    if (logoStoragePath != null) map['logoStoragePath'] = logoStoragePath;
    await _church(churchId).set(map, SetOptions(merge: true));
  }
}
