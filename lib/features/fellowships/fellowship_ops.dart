import '../../core/utils/text_case_utils.dart';
import '../church/data/church_settings_repository.dart';
import '../operations/record_ops_repository.dart';
import 'fellowship_match.dart';

/// Creates fellowships.
///
/// Groups are names on partners, plus an optional catalog on the church so a
/// new group can exist before anyone is assigned to it. Rename, merge,
/// dissolve and move rewrite partners in bulk, so they run on the server —
/// see [RecordOpsRepository.fellowshipChange] — where they are recorded and
/// can be undone.
class FellowshipOps {
  FellowshipOps(this._church);

  final ChurchSettingsRepository _church;

  Future<void> create({
    required String churchId,
    required String name,
    required List<String> catalog,
    required Iterable<String> partnerFellowships,
  }) async {
    final label = TextCaseUtils.toTitleCase(name);
    if (label.isEmpty) return;
    final known = mergeKnownFellowships(catalog, partnerFellowships);
    if (known.any((n) => fellowshipNamesMatch(n, label))) return;
    await _church.setFellowshipNames(churchId, [...known, label]);
  }
}
