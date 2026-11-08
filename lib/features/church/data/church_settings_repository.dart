import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/constants/firebase_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/text_case_utils.dart';
import '../domain/church_settings.dart';
import '../domain/exchange_rates.dart';
import '../domain/monthly_email_report.dart';

class ChurchSettingsRepository {
  ChurchSettingsRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

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
    if (name != null) map['name'] = TextCaseUtils.toTitleCase(name);
    if (primaryColorHex != null) map['primaryColorHex'] = primaryColorHex;
    if (logoUrl != null) map['logoUrl'] = logoUrl;
    if (logoStoragePath != null) map['logoStoragePath'] = logoStoragePath;
    await _church(churchId).set(map, SetOptions(merge: true));
  }

  Future<void> updateLocaleCurrency({
    required String churchId,
    required String currency,
    required String currencySymbol,
  }) async {
    await _church(churchId).set({
      'currency': currency.toUpperCase(),
      'currencySymbol': currencySymbol,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setFellowshipNames(String churchId, List<String> names) async {
    final cleaned = [
      for (final n in names)
        if (n.trim().isNotEmpty) TextCaseUtils.toTitleCase(n.trim()),
    ];
    await _church(churchId).update({
      'settings.fellowshipNames': cleaned,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> completeSetup(String churchId) async {
    await _church(churchId).set({
      'churchSetupCompletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateExchangeRates({
    required String churchId,
    required ChurchExchangeRates rates,
  }) async {
    await _church(churchId).update({
      'settings.exchangeRates': rates.toFirestoreMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMonthlyPartnerEmail({
    required String churchId,
    required bool enabled,
    required String? primaryPastorUid,
    required String? partnerEmailFrom,
  }) async {
    final from = partnerEmailFrom?.trim();
    await _church(churchId).set({
      'settings': {
        'sendMonthlyPartnerEmails': enabled,
        'primaryPastorUid':
            (primaryPastorUid == null || primaryPastorUid.isEmpty)
                ? null
                : primaryPastorUid,
        'partnerEmailFrom': (from == null || from.isEmpty) ? null : from,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<MonthlyEmailReport?> watchLatestMonthlyEmailReport(String churchId) {
    return _church(churchId)
        .collection('monthly_email_reports')
        .orderBy('ranAt', descending: true)
        .limit(1)
        .snapshots()
        .map((s) {
      if (s.docs.isEmpty) return null;
      return MonthlyEmailReport.fromDoc(s.docs.first);
    });
  }

  /// The last year of monthly runs, newest first.
  Stream<List<MonthlyEmailReport>> watchMonthlyEmailReports(String churchId) {
    return _church(churchId)
        .collection('monthly_email_reports')
        .orderBy('ranAt', descending: true)
        .limit(12)
        .snapshots()
        .map((s) => s.docs.map(MonthlyEmailReport.fromDoc).toList());
  }

  /// Every letter recorded for one month (YYYY-MM).
  Stream<List<MonthlyEmailDelivery>> watchMonthlyEmailDeliveries(
    String churchId,
    String yearMonth,
  ) {
    return _church(churchId)
        .collection('monthly_email_deliveries')
        .where('yearMonth', isEqualTo: yearMonth)
        .snapshots()
        .map((s) => s.docs.map(MonthlyEmailDelivery.fromDoc).toList());
  }

  Future<String> previewMonthlyPartnerEmail() async {
    try {
      final callable = _functions.httpsCallable(
        FirebaseConstants.previewMonthlyPartnerGivingEmail,
      );
      final result = await callable.call(<String, dynamic>{});
      final data = Map<String, dynamic>.from(result.data as Map? ?? {});
      return data['to'] as String? ?? '';
    } on FirebaseFunctionsException catch (e) {
      throw AppException(e.message ?? 'Could not send preview.', code: e.code);
    }
  }

  Future<({int sent, int sentNow, int skipped, int failed, bool dryRun, String yearMonth})>
      runMonthlyPartnerEmails({String? yearMonth, List<String>? partnerIds}) async {
    try {
      final callable = _functions.httpsCallable(
        FirebaseConstants.runMonthlyPartnerGivingSummary,
      );
      // A month already run sends only to those not sent yet; with
      // partnerIds it sends to just those, even if they already had it.
      final result = await callable.call(<String, dynamic>{
        'yearMonth': ?yearMonth,
        'partnerIds': ?partnerIds,
      });
      final data = Map<String, dynamic>.from(result.data as Map? ?? {});
      return (
        sent: (data['sent'] as num?)?.toInt() ?? 0,
        sentNow: (data['sentNow'] as num?)?.toInt() ?? 0,
        skipped: (data['skippedNoEmail'] as num?)?.toInt() ?? 0,
        failed: (data['failed'] as num?)?.toInt() ?? 0,
        dryRun: data['dryRun'] == true,
        yearMonth: data['yearMonth'] as String? ?? '',
      );
    } on FirebaseFunctionsException catch (e) {
      throw AppException(e.message ?? 'Could not send monthly emails.', code: e.code);
    }
  }
}
