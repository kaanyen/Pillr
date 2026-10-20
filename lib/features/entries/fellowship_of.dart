import '../../core/utils/text_case_utils.dart';
import 'domain/partnership_entry.dart';

/// Fellowship on the entry snapshot, or the partner's current group if the
/// snapshot never stored one. Older rows often have only a name.
String fellowshipRawOf(
  PartnershipEntry entry, [
  Map<String, String> fellowshipByPartnerId = const {},
]) {
  final snap = entry.partnerSnapshot['fellowship']?.toString().trim() ?? '';
  if (snap.isNotEmpty) return snap;
  return fellowshipByPartnerId[entry.partnerId]?.trim() ?? '';
}

String fellowshipKeyOf(
  PartnershipEntry entry, [
  Map<String, String> fellowshipByPartnerId = const {},
]) =>
    fellowshipRawOf(entry, fellowshipByPartnerId).toLowerCase();

String fellowshipLabelOf(
  PartnershipEntry entry, [
  Map<String, String> fellowshipByPartnerId = const {},
]) {
  final raw = fellowshipRawOf(entry, fellowshipByPartnerId);
  if (raw.isEmpty) return 'No fellowship';
  return TextCaseUtils.toTitleCase(raw);
}
