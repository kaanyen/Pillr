import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/text_case_utils.dart';

import 'exchange_rates.dart';

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
    this.exchangeRates = const ChurchExchangeRates(),
    this.churchSetupCompletedAt,
    this.isActive = true,
    this.sendMonthlyPartnerEmails = false,
    this.primaryPastorUid,
    this.partnerEmailFrom,
    this.fellowshipNames = const [],
  });

  final String churchId;
  final String? name;
  final String? primaryColorHex;
  final String? logoUrl;
  final String? logoStoragePath;
  final String? currency;
  final String? currencySymbol;
  final ChurchExchangeRates exchangeRates;
  final DateTime? churchSetupCompletedAt;
  final bool isActive;
  final bool sendMonthlyPartnerEmails;
  final String? primaryPastorUid;
  final String? partnerEmailFrom;

  /// Groups the church has created, including empty ones.
  final List<String> fellowshipNames;

  static ChurchSettings? fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    return fromData(doc.id, data);
  }

  static ChurchSettings fromData(String churchId, Map<String, dynamic> data) {
    final rawName = data['name'] as String?;
    final hex = data['primaryColorHex'] as String? ?? data['primaryColor'] as String?;
    final setup = data['churchSetupCompletedAt'];
    DateTime? setupAt;
    if (setup is Timestamp) setupAt = setup.toDate();
    final rawSettings = data['settings'];
    final settings = rawSettings is Map
        ? Map<String, dynamic>.from(rawSettings)
        : <String, dynamic>{};
    final from = (settings['partnerEmailFrom'] as String?)?.trim();
    final pastorUid = (settings['primaryPastorUid'] as String?)?.trim();
    final rawFellowships = settings['fellowshipNames'];
    final fellowshipNames = rawFellowships is List
        ? [
            for (final n in rawFellowships)
              if (n is String && n.trim().isNotEmpty)
                TextCaseUtils.toTitleCase(n),
          ]
        : const <String>[];
    return ChurchSettings(
      churchId: churchId,
      name: rawName == null || rawName.trim().isEmpty ? null : TextCaseUtils.toTitleCase(rawName),
      primaryColorHex: hex,
      logoUrl: data['logoUrl'] as String?,
      logoStoragePath: data['logoStoragePath'] as String?,
      currency: data['currency'] as String?,
      currencySymbol: data['currencySymbol'] as String?,
      exchangeRates: ChurchExchangeRates.fromSettings(settings),
      churchSetupCompletedAt: setupAt,
      isActive: data['isActive'] != false,
      sendMonthlyPartnerEmails: settings['sendMonthlyPartnerEmails'] == true,
      primaryPastorUid: pastorUid == null || pastorUid.isEmpty ? null : pastorUid,
      partnerEmailFrom: from == null || from.isEmpty ? null : from,
      fellowshipNames: fellowshipNames,
    );
  }
}
