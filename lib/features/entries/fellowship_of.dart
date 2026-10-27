import '../../core/utils/text_case_utils.dart';
import 'domain/partnership_entry.dart';

/// The partner's current fellowship, or the name frozen on the entry if we
/// have no live partner. Snapshots are a copy from record time — a rename
/// on the partner book must win, or Fellowships keeps showing the old group.
String fellowshipRawOf(
  PartnershipEntry entry, [
  Map<String, String> fellowshipByPartnerId = const {},
]) {
  final live = fellowshipByPartnerId[entry.partnerId]?.trim() ?? '';
  if (live.isNotEmpty) return live;
  return entry.partnerSnapshot['fellowship']?.toString().trim() ?? '';
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
