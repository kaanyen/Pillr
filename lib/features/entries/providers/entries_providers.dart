import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';
import '../../partners/providers/partners_providers.dart';
import '../../periods/providers/periods_providers.dart';
import '../data/entries_repository.dart';
import '../domain/partnership_entry.dart';
import '../monthly_records_index.dart';
import 'monthly_records_entries_provider.dart';

final entriesRepositoryProvider = Provider<EntriesRepository>((ref) {
  return EntriesRepository(ref.watch(firestoreProvider));
});

/// Approved entries for the active period — the working set for every ranking.
///
/// This replaced `entriesListProvider` as the source for rankings. That one
/// streamed the church's entire `entries` collection, live, to five screens at
/// once: 800+ documents re-parsed on every write, and re-downloaded on every
/// navigation because it is `autoDispose` and web keeps no Firestore cache.
///
/// Rankings only ever consumed approved entries in one period, so that is what
/// this asks Firestore for. With no active period it falls back to every
/// approved entry, which is what the old all-time ranking showed.
///
/// The role split is carried over intact: a pastor ranks the whole church, a
/// staff member ranks what they recorded.
final rankingEntriesProvider =
    StreamProvider.autoDispose<List<PartnershipEntry>>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value([]);
  final period = ref.watch(activePeriodProvider);
  return ref.watch(entriesRepositoryProvider).watchApprovedEntriesForRanking(
        idx.churchId,
        periodId: period?.id,
        createdByUid: idx.isPastor ? null : idx.uid,
      );
});

/// Status counts and the approved total, from Firestore's aggregate index.
///
/// Pastor: the whole church. Staff: their own submissions.
///
/// A `Future`, not a stream — aggregates have no snapshot API. The pending
/// count, the one a pastor watches change, still comes live off
/// [pendingEntriesProvider]; see `pastorEntryStatsProvider`. Everything else
/// here is refreshed by [invalidateEntryDerivedData] after the app itself
/// writes an entry.
final entryStatusTotalsProvider =
    FutureProvider.autoDispose<EntryStatusTotals>((ref) async {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return EntryStatusTotals.empty;
  return ref.watch(entriesRepositoryProvider).fetchEntryStatusTotals(
        idx.churchId,
        createdByUid: idx.isPastor ? null : idx.uid,
      );
});

/// Refreshes everything derived from entries after a write.
///
/// The rankings and the pending queue are live and need no help. The aggregate
/// totals are not, so anything that creates, edits, approves, declines or
/// deletes an entry has to say so here.
///
/// Monthly records are not live either: they are paged in by hand and held in
/// a notifier, so approving an entry — the write that puts it into that view
/// in the first place, since the view asks only for approved rows — left the
/// pastor looking at a list assembled before the approval, and month totals
/// computed without it. Invalidating drops the pages; the screen reloads from
/// the first one when it is next built.
void invalidateEntryDerivedData(WidgetRef ref) {
  ref.invalidate(entryStatusTotalsProvider);
  ref.invalidate(monthlyRecordsEntriesProvider);
}

/// Every entry the signed-in user may export, read a page at a time.
///
/// Exports still cover the whole archive. The difference is that the rows are
/// fetched when someone presses the button rather than streamed and held for
/// the whole session against the chance that they might.
Future<List<PartnershipEntry>> loadEntriesForExport(WidgetRef ref) async {
  final idx = ref.read(userChurchIndexProvider).valueOrNull;
  if (idx == null) return const [];
  return ref.read(entriesRepositoryProvider).fetchAllEntriesForExport(
        idx.churchId,
        allChurchEntries: idx.isPastor,
        createdByUid: idx.isPastor ? null : idx.uid,
      );
}

final pendingEntriesProvider = StreamProvider.autoDispose<List<PartnershipEntry>>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null || !idx.isPastor) return Stream.value([]);
  return ref.watch(entriesRepositoryProvider).watchPendingEntries(idx.churchId);
});

/// Entries decided in the last day — the strip under the review queue.
///
/// [since] is passed in rather than read from the clock here so the screen
/// controls the moving edge; it already re-reads the clock on a timer.
final recentlyDecidedProvider = StreamProvider.autoDispose
    .family<List<PartnershipEntry>, DateTime>((ref, since) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value([]);
  return ref
      .watch(entriesRepositoryProvider)
      .watchRecentlyDecided(idx.churchId, since);
});

final pendingApprovalCountProvider = Provider<int>((ref) {
  return ref.watch(pendingEntriesProvider).maybeWhen(data: (e) => e.length, orElse: () => 0);
});

/// Staff: sum of **approved** entry amounts the signed-in user created, grouped by partner.
/// Pastors should use [Partner.totalApprovedAmount] instead; this map is empty for non-staff.
final staffApprovedTotalsByPartnerProvider = StreamProvider.autoDispose<Map<String, double>>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null || !idx.isStaff) {
    return Stream.value({});
  }
  return ref.watch(entriesRepositoryProvider).watchMyEntries(idx.churchId, idx.uid).map((entries) {
    final map = <String, double>{};
    for (final e in entries) {
      if (e.status != 'approved') continue;
      map[e.partnerId] = (map[e.partnerId] ?? 0) + e.amountCedis;
    }
    return map;
  });
});

/// Per-partner slice of [staffApprovedTotalsByPartnerProvider] (0 if loading or pastor).
final staffApprovedTotalForPartnerProvider = Provider.family<double, String>((ref, partnerId) {
  final async = ref.watch(staffApprovedTotalsByPartnerProvider);
  return async.maybeWhen(
    data: (m) => m[partnerId] ?? 0,
    orElse: () => 0,
  );
});

final monthlyRecordsIndexProvider =
    Provider.autoDispose<MonthlyRecordsIndex>((ref) {
  final entries = ref.watch(monthlyRecordsEntriesProvider).entries;
  final byPartner = ref.watch(partnerFellowshipByIdProvider);
  return MonthlyRecordsIndex.build(
    entries,
    fellowshipByPartnerId: byPartner,
  );
});

final partnerEntriesProvider =
    StreamProvider.autoDispose.family<List<PartnershipEntry>, String>((ref, partnerId) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value([]);
  return ref.watch(entriesRepositoryProvider).watchPartnerEntries(idx.churchId, partnerId);
});

final entryDetailProvider =
    StreamProvider.autoDispose.family<PartnershipEntry?, String>((ref, entryId) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value(null);
  return ref.watch(entriesRepositoryProvider).watchEntry(idx.churchId, entryId);
});
