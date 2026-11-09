import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';
import '../../church/providers/church_settings_providers.dart';
import '../../entries/providers/entries_providers.dart';
import '../../fellowships/fellowship_match.dart';
import '../data/partners_repository.dart';
import '../domain/partner.dart';

final partnersRepositoryProvider = Provider<PartnersRepository>((ref) {
  return PartnersRepository(ref.watch(firestoreProvider));
});

final partnersStreamProvider = StreamProvider.autoDispose
    .family<List<Partner>, bool>((ref, includeInactive) {
      final idx = ref.watch(userChurchIndexProvider).valueOrNull;
      if (idx == null) return Stream.value([]);
      return ref
          .watch(partnersRepositoryProvider)
          .watchPartners(idx.churchId, includeInactive: includeInactive);
    });

/// For staff, the partners they have recorded giving for, in any state.
/// Null for everyone else, who see the whole book.
final myPartnerIdsProvider = StreamProvider.autoDispose<Set<String>?>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null || !idx.isStaff) return Stream.value(null);
  return ref
      .watch(entriesRepositoryProvider)
      .watchMyEntries(idx.churchId, idx.uid)
      .map((es) => {for (final e in es) e.partnerId});
});

/// The partners this person browses in lists: the whole book for pastors and
/// admins; for staff, only those they work with — the partners they have
/// recorded giving for. Finding someone new to record for still searches the
/// whole book (the partner picker, search, an import's matching).
final visiblePartnersProvider = Provider.autoDispose
    .family<AsyncValue<List<Partner>>, bool>((ref, includeInactive) {
      final all = ref.watch(partnersStreamProvider(includeInactive));
      final mine = ref.watch(myPartnerIdsProvider);
      if (mine.isLoading && !mine.hasValue) return const AsyncLoading();
      final ids = mine.valueOrNull;
      if (ids == null) return all;
      return all.whenData((ps) => [for (final p in ps) if (ids.contains(p.id)) p]);
    });

/// Current fellowship per partner id — used when an entry snapshot omitted it.
final partnerFellowshipByIdProvider = Provider.autoDispose<Map<String, String>>(
  (ref) {
    final partners =
        ref.watch(partnersStreamProvider(false)).valueOrNull ?? const [];
    return {for (final p in partners) p.id: p.fellowship};
  },
);

/// Catalog plus names already on partners — the church's fellowship book.
final knownFellowshipsProvider = Provider.autoDispose<List<String>>((ref) {
  final catalog =
      ref.watch(churchSettingsProvider).valueOrNull?.fellowshipNames ??
      const [];
  final partners =
      ref.watch(partnersStreamProvider(false)).valueOrNull ?? const [];
  return mergeKnownFellowships(catalog, partners.map((p) => p.fellowship));
});

final partnerStreamProvider = StreamProvider.autoDispose
    .family<Partner?, String>((ref, partnerId) {
      final idx = ref.watch(userChurchIndexProvider).valueOrNull;
      if (idx == null) return Stream.value(null);
      return ref
          .watch(partnersRepositoryProvider)
          .watchPartner(idx.churchId, partnerId);
    });
