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
    this.letterSubject,
    this.letterHeading,
    this.letterMessage,
    this.letterSignOff,
    this.logoAspect,
    this.exchangeRatesUpdatedAt,
    this.exchangeRatesUpdatedBy,
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

  /// The church's own words for the monthly letter; null uses Pillr's.
  /// [First name], [Month] and [Church name] are filled in per partner.
  final String? letterSubject;
  final String? letterHeading;
  final String? letterMessage;
  final String? letterSignOff;

  /// The logo's width divided by its height, noted when it is uploaded: a
  /// wide logo is unreadable at sidebar size, so the initials show there.
  final double? logoAspect;

  final DateTime? exchangeRatesUpdatedAt;
  final String? exchangeRatesUpdatedBy;

  /// Whether the logo is square enough to read in the sidebar.
  bool get logoFitsSidebar =>
      logoUrl != null && (logoAspect == null || (logoAspect! >= 0.66 && logoAspect! <= 1.5));

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
      letterSubject: _text(settings['letterSubject']),
      letterHeading: _text(settings['letterHeading']),
      letterMessage: _text(settings['letterMessage']),
      letterSignOff: _text(settings['letterSignOff']),
      logoAspect: (settings['logoAspect'] as num?)?.toDouble(),
      exchangeRatesUpdatedAt: settings['exchangeRatesUpdatedAt'] is Timestamp
          ? (settings['exchangeRatesUpdatedAt'] as Timestamp).toDate()
          : null,
      exchangeRatesUpdatedBy: _text(settings['exchangeRatesUpdatedBy']),
      primaryPastorUid: pastorUid == null || pastorUid.isEmpty ? null : pastorUid,
      partnerEmailFrom: from == null || from.isEmpty ? null : from,
      fellowshipNames: fellowshipNames,
    );
  }

  static String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
}
