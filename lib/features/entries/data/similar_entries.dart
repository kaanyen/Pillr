import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firebase_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../auth/providers/auth_providers.dart';

/// One entry about to be recorded, to check against what is already in Pillr.
typedef SimilarCandidate = ({
  String key,
  String partnerId,
  String armId,
  String periodId,
  double amountCedis,
  DateTime dateGiven,
});

/// Asks the server which new entries look like ones already in Pillr — the
/// same partner, arm and period, the same day, within 10%.
///
/// Staff cannot read entries other staff recorded, so the comparison runs
/// on the server, and the answer is only which of the new ones look like
/// duplicates: nothing about the entries they match.
class SimilarEntries {
  SimilarEntries(this._functions);

  final FirebaseFunctions _functions;

  Future<Set<String>> check(List<SimilarCandidate> candidates) async {
    if (candidates.isEmpty) return const {};
    try {
      final out = <String>{};
      for (var i = 0; i < candidates.length; i += 500) {
        final slice = candidates.skip(i).take(500);
        final r = await _functions.httpsCallable(FirebaseConstants.findSimilarEntries).call(<String, dynamic>{
          'candidates': [
            for (final c in slice)
              {
                'key': c.key,
                'partnerId': c.partnerId,
                'armId': c.armId,
                'periodId': c.periodId,
                'amountCedis': c.amountCedis,
                'dateGivenMs': c.dateGiven.millisecondsSinceEpoch,
              },
          ],
        });
        final data = Map<String, dynamic>.from(r.data as Map? ?? {});
        out.addAll(((data['similar'] as List?) ?? const []).whereType<String>());
      }
      return out;
    } on FirebaseFunctionsException catch (e) {
      throw AppException(e.message ?? 'Could not check for duplicates.', code: e.code);
    }
  }
}

final similarEntriesProvider = Provider<SimilarEntries>(
  (ref) => SimilarEntries(ref.watch(firebaseFunctionsProvider)),
);
