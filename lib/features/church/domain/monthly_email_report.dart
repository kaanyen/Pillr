import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_utils.dart';

class MonthlyEmailSkip {
  const MonthlyEmailSkip({
    required this.partnerId,
    required this.fullName,
    required this.memberId,
    required this.amount,
  });

  final String partnerId;
  final String fullName;
  final String memberId;
  final double amount;

  factory MonthlyEmailSkip.fromMap(Map<String, dynamic> m) {
    return MonthlyEmailSkip(
      partnerId: m['partnerId'] as String? ?? '',
      fullName: m['fullName'] as String? ?? '',
      memberId: m['memberId'] as String? ?? '',
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

class MonthlyEmailFailure {
  const MonthlyEmailFailure({
    required this.partnerId,
    required this.fullName,
    required this.email,
    required this.error,
  });

  final String partnerId;
  final String fullName;
  final String email;
  final String error;

  factory MonthlyEmailFailure.fromMap(Map<String, dynamic> m) {
    return MonthlyEmailFailure(
      partnerId: m['partnerId'] as String? ?? '',
      fullName: m['fullName'] as String? ?? '',
      email: m['email'] as String? ?? '',
      error: m['error'] as String? ?? '',
    );
  }
}

class MonthlyEmailReport {
  const MonthlyEmailReport({
    required this.yearMonth,
    required this.monthLabel,
    required this.sent,
    required this.skippedNoEmail,
    required this.failed,
    required this.dryRun,
    this.skippedOptedOut = const [],
    this.skipReason,
    this.ranAt,
  });

  final String yearMonth;
  final String monthLabel;
  final int sent;
  final List<MonthlyEmailSkip> skippedNoEmail;
  final List<MonthlyEmailFailure> failed;

  /// Partners whose letters the church turned off.
  final List<MonthlyEmailSkip> skippedOptedOut;
  final bool dryRun;
  final String? skipReason;
  final DateTime? ranAt;

  factory MonthlyEmailReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final skipped = ((m['skippedNoEmail'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MonthlyEmailSkip.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    final failed = ((m['failed'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MonthlyEmailFailure.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    final optedOut = ((m['skippedOptedOut'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MonthlyEmailSkip.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    return MonthlyEmailReport(
      skippedOptedOut: optedOut,
      yearMonth: m['yearMonth'] as String? ?? d.id,
      monthLabel: m['monthLabel'] as String? ?? d.id,
      sent: (m['sent'] as num?)?.toInt() ?? 0,
      skippedNoEmail: skipped,
      failed: failed,
      dryRun: m['dryRun'] == true,
      skipReason: m['skipReason'] as String?,
      ranAt: timestampToDateTime(m['ranAt']),
    );
  }
}

/// One letter that went out (or was a dry run), from monthly_email_deliveries.
class MonthlyEmailDelivery {
  const MonthlyEmailDelivery({
    required this.partnerId,
    required this.yearMonth,
    required this.email,
    required this.amount,
    required this.status,
    this.sentAt,
  });

  final String partnerId;
  final String yearMonth;
  final String email;
  final double amount;

  /// sent | dry_run
  final String status;
  final DateTime? sentAt;

  factory MonthlyEmailDelivery.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return MonthlyEmailDelivery(
      partnerId: m['partnerId'] as String? ?? '',
      yearMonth: m['yearMonth'] as String? ?? '',
      email: m['email'] as String? ?? '',
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      status: m['status'] as String? ?? '',
      sentAt: timestampToDateTime(m['sentAt']),
    );
  }
}

