import 'package:cloud_firestore/cloud_firestore.dart';

/// `churches/{churchId}` document fields used for branding and display.
class ChurchSettings {
  const ChurchSettings({
    required this.churchId,
    this.name,
    this.primaryColorHex,
    this.logoUrl,
    this.logoStoragePath,
  });

  final String churchId;
  final String? name;
  final String? primaryColorHex;
  final String? logoUrl;
  final String? logoStoragePath;

  static ChurchSettings? fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    return ChurchSettings(
      churchId: doc.id,
      name: data['name'] as String?,
      primaryColorHex: data['primaryColorHex'] as String?,
      logoUrl: data['logoUrl'] as String?,
      logoStoragePath: data['logoStoragePath'] as String?,
    );
  }
}
