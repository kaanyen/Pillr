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
    double? logoAspect,
  }) async {
    final map = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (logoAspect != null) map['settings'] = {'logoAspect': logoAspect};
    if (name != null) map['name'] = TextCaseUtils.toTitleCase(name);
    if (primaryColorHex != null) map['primaryColorHex'] = primaryColorHex;
    if (logoUrl != null) map['logoUrl'] = logoUrl;
    if (logoStoragePath != null) map['logoStoragePath'] = logoStoragePath;
    await _church(churchId).set(map, SetOptions(merge: true));
  }

  /// Takes the logo off; the initials show again. The file stays in storage,
  /// so [restoreLogo] can put it straight back.
  Future<void> removeLogo(String churchId) async {
    await _church(churchId).update({
      'logoUrl': null,
      'logoStoragePath': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> restoreLogo(String churchId, {required String url, required String? path}) async {
    await _church(churchId).update({
      'logoUrl': url,
      'logoStoragePath': path,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
    String? byName,
  }) async {
    await _church(churchId).update({
      'settings.exchangeRates': rates.toFirestoreMap(),
      'settings.exchangeRatesUpdatedAt': FieldValue.serverTimestamp(),
      'settings.exchangeRatesUpdatedBy': byName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMonthlyPartnerEmail({
    required String churchId,
    required bool enabled,
    required String? primaryPastorUid,
    required String? partnerEmailFrom,
    LetterWordingDraft? wording,
  }) async {
    final from = partnerEmailFrom?.trim();
    String? clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    await _church(churchId).set({
      'settings': {
        if (wording != null) ...{
          'letterSubject': clean(wording.subject),
          'letterHeading': clean(wording.heading),
          'letterMessage': clean(wording.message),
          'letterSignOff': clean(wording.signOff),
        },
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

  /// The thank-you sent when a pastor approves giving: on or off by email
  /// and by text, and the church's words for each.
  Future<void> updateApprovalMessages({
    required String churchId,
    required bool emailOn,
    required bool smsOn,
    required String emailSubject,
    required String emailMessage,
    required String smsMessage,
    required String smsSenderId,
    required bool partnerPageOn,
  }) async {
    String? clean(String v) => v.trim().isEmpty ? null : v.trim();
    await _church(churchId).set({
      'settings': {
        'partnerPageOn': partnerPageOn,
        'approvalEmailOn': emailOn,
        'approvalSmsOn': smsOn,
        'approvalEmailSubject': clean(emailSubject),
        'approvalEmailMessage': clean(emailMessage),
        'approvalSmsMessage': clean(smsMessage),
        'smsSenderId': clean(smsSenderId),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Sends the caller a test: the email to their own address, or the text to
  /// [phone]. Returns where it went, and whether it was only a dry run.
  Future<({String to, bool dryRun})> testApprovalMessage({
    required String channel,
    String? subject,
    required String message,
    String? phone,
    String? senderId,
  }) async {
    try {
      final r = await _functions.httpsCallable(FirebaseConstants.testApprovalMessage).call(<String, dynamic>{
        'channel': channel,
        'subject': ?subject,
        'message': message,
        'phone': ?phone,
        'senderId': ?senderId,
      });
      final d = Map<String, dynamic>.from(r.data as Map? ?? {});
      return (to: d['to'] as String? ?? '', dryRun: d['dryRun'] == true);
    } on FirebaseFunctionsException catch (e) {
      throw AppException(e.message ?? 'The test did not send.', code: e.code);
    }
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

  Future<String> previewMonthlyPartnerEmail({LetterWordingDraft? wording}) async {
    try {
      final callable = _functions.httpsCallable(
        FirebaseConstants.previewMonthlyPartnerGivingEmail,
      );
      final result = await callable.call(<String, dynamic>{
        if (wording != null)
          'wording': {
            'subject': wording.subject,
            'heading': wording.heading,
            'message': wording.message,
            'signOff': wording.signOff,
          },
      });
      final data = Map<String, dynamic>.from(result.data as Map? ?? {});
      return data['to'] as String? ?? '';
    } on FirebaseFunctionsException catch (e) {
      throw AppException(e.message ?? 'Could not send preview.', code: e.code);
    }
  }

  Future<MonthlyEmailRunResult> runMonthlyPartnerEmails({String? yearMonth, List<String>? partnerIds}) async {
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

/// The church's words for the monthly letter, as typed on Settings.
typedef LetterWordingDraft = ({String subject, String heading, String message, String signOff});

/// What one run of the monthly letters did.
typedef MonthlyEmailRunResult = ({int sent, int sentNow, int skipped, int failed, bool dryRun, String yearMonth});

