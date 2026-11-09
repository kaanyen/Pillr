import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/text_case_utils.dart';

class Partner {
  const Partner({
    required this.id,
    required this.churchId,
    required this.memberId,
    required this.fullName,
    required this.fellowship,
    this.email,
    this.phone,
    required this.isActive,
    required this.totalApprovedAmount,
    required this.entryCount,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.mergedInto,
    this.formerMemberIds = const [],
    this.mergedAliases = const [],
    this.phones = const [],
    this.emails = const [],
    this.address,
    this.notes,
    this.followUpReason,
    this.noMonthlyLetters = false,
  });

  final String id;
  final String churchId;
  final String memberId;
  final String fullName;
  final String fellowship;
  final String? email;
  final String? phone;
  final bool isActive;
  final double totalApprovedAmount;
  final int entryCount;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set when this record was merged into another and closed. The other id
  /// is where its giving now lives.
  final String? mergedInto;

  /// Every member ID this person was known by before a merge gave them their
  /// current one. Search and imports find them by any of these.
  final List<String> formerMemberIds;

  /// The records merged into this one: their id, name and member ID, so any
  /// of them can be separated again.
  final List<MergedRecord> mergedAliases;

  /// Every phone number and email this person has, after merges brought
  /// several records together. [phone] and [email] are the main ones.
  final List<String> phones;
  final List<String> emails;

  final String? address;

  /// Anything the church wants to remember about this person.
  final String? notes;

  /// Why this partner has gone quiet, as last noted on Follow up
  /// ("Called 12 Oct, travelling").
  final String? followUpReason;

  /// The church turned this partner's monthly thank-you letter off.
  final bool noMonthlyLetters;

  /// [phones] with [phone] first, each once — what to show and compare.
  List<String> get allPhones => _distinctContacts([phone ?? '', ...phones]);
  List<String> get allEmails => _distinctContacts([email ?? '', ...emails]);

  String get displayLabel => '$memberId · $fullName · $fellowship';

  factory Partner.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Partner(
      id: d.id,
      churchId: m['churchId'] as String? ?? '',
      memberId: m['memberId'] as String? ?? '',
      fullName: TextCaseUtils.toTitleCase(m['fullName'] as String? ?? ''),
      fellowship: TextCaseUtils.toTitleCase(m['fellowship'] as String? ?? ''),
      email: m['email'] as String?,
      phone: m['phone'] as String?,
      isActive: m['isActive'] as bool? ?? true,
      totalApprovedAmount: storedTotalCedis(
        m,
        pesewasKey: 'totalApprovedPesewas',
        cedisKey: 'totalApprovedAmount',
      ),
      entryCount: (m['entryCount'] as num?)?.toInt() ?? 0,
      createdBy: m['createdBy'] as String? ?? '',
      createdAt: timestampToDateTime(m['createdAt']) ?? DateTime.now(),
      updatedAt: timestampToDateTime(m['updatedAt']) ?? DateTime.now(),
      mergedInto: (m['mergedInto'] as String?)?.trim().isEmpty ?? true
          ? null
          : (m['mergedInto'] as String).trim(),
      formerMemberIds: [
        for (final f in (m['formerMemberIds'] as List? ?? const []))
          if (f.toString().trim().isNotEmpty) f.toString().trim().toUpperCase(),
      ],
      mergedAliases: [
        for (final a in (m['mergedAliases'] as List? ?? const []))
          if (a is Map) MergedRecord.fromMap(a.cast<String, dynamic>()),
      ],
      phones: _strings(m['phones']),
      emails: _strings(m['emails']),
      address: m['address'] as String?,
      notes: m['notes'] as String?,
      followUpReason: m['followUpReason'] as String?,
      noMonthlyLetters: m['noMonthlyLetters'] as bool? ?? false,
    );
  }
}

List<String> _strings(Object? v) => [
  for (final x in (v as List? ?? const []))
    if (x.toString().trim().isNotEmpty) x.toString().trim(),
];

List<String> _distinctContacts(List<String> values) {
  final seen = <String>{};
  final out = <String>[];
  for (final v in values) {
    final t = v.trim();
    if (t.isEmpty) continue;
    final digits = t.replaceAll(RegExp(r'\D'), '');
    final key = t.contains('@')
        ? t.toLowerCase()
        : (digits.length >= 9 ? digits.substring(digits.length - 9) : digits);
    if (seen.add(key)) out.add(t);
  }
  return out;
}

/// One record that became part of a merged partner: its id, name, member
/// ID and contacts as they were, so it can be told apart and taken out again.
class MergedRecord {
  const MergedRecord({
    required this.partnerId,
    required this.fullName,
    required this.memberId,
    this.fellowship = '',
    this.phones = const [],
    this.emails = const [],
    this.self = false,
  });

  factory MergedRecord.fromMap(Map<String, dynamic> m) => MergedRecord(
    partnerId: m['partnerId'] as String? ?? '',
    fullName: m['fullName'] as String? ?? '',
    memberId: (m['memberId'] as String? ?? '').trim().toUpperCase(),
    fellowship: m['fellowship'] as String? ?? '',
    phones: _distinctContacts([
      m['phone'] as String? ?? '',
      ..._strings(m['phones']),
    ]),
    emails: _distinctContacts([
      m['email'] as String? ?? '',
      ..._strings(m['emails']),
    ]),
    self: m['self'] == true,
  );

  final String partnerId;
  final String fullName;
  final String memberId;
  final String fellowship;
  final List<String> phones;
  final List<String> emails;

  /// The record that was kept in the merge, as it was before.
  final bool self;
}
