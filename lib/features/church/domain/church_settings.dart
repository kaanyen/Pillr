import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/text_case_utils.dart';

/// `churches/{churchId}` document fields used for branding and display.
class ChurchSettings {
  const ChurchSettings({
    required this.churchId,
    this.name,
    this.primaryColorHex,
    this.logoUrl,
    this.logoStoragePath,
    this.currency,
    this.currencySymbol,
    this.churchSetupCompletedAt,
    this.isActive = true,
  });

  final String churchId;
  final String? name;
  final String? primaryColorHex;
  final String? logoUrl;
  final String? logoStoragePath;
  final String? currency;
  final String? currencySymbol;
  final DateTime? churchSetupCompletedAt;
  final bool isActive;

  static ChurchSettings? fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final rawName = data['name'] as String?;
    final hex = data['primaryColorHex'] as String? ?? data['primaryColor'] as String?;
    final setup = data['churchSetupCompletedAt'];
    DateTime? setupAt;
    if (setup is Timestamp) setupAt = setup.toDate();
    return ChurchSettings(
      churchId: doc.id,
      name: rawName == null || rawName.trim().isEmpty ? null : TextCaseUtils.toTitleCase(rawName),
      primaryColorHex: hex,
      logoUrl: data['logoUrl'] as String?,
      logoStoragePath: data['logoStoragePath'] as String?,
      currency: data['currency'] as String?,
      currencySymbol: data['currencySymbol'] as String?,
      churchSetupCompletedAt: setupAt,
      isActive: data['isActive'] != false,
    );
  }
}
