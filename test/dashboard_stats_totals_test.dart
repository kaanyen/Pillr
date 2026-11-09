import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/auth/domain/user_church_index.dart';
import 'package:the_pillr/features/auth/providers/auth_providers.dart';
import 'package:the_pillr/features/dashboard/providers/dashboard_stats_providers.dart';
import 'package:the_pillr/features/entries/data/entries_repository.dart';
import 'package:the_pillr/features/entries/providers/entries_providers.dart';

/// A failed aggregate must not read as zero giving. Production showed ₵0.00
/// for a church with ₵2m approved because a missing index made the count
/// query throw and the provider quietly fell back to empty totals.
void main() {
  ProviderContainer containerFor(
    String role,
    AsyncValue<EntryStatusTotals> totals,
  ) {
    final c = ProviderContainer(overrides: [
      userChurchIndexProvider.overrideWithValue(AsyncData(
          UserChurchIndex(uid: 'u1', churchId: 'demo-church', role: role))),
      entryStatusTotalsProvider.overrideWithValue(totals),
      pendingEntriesProvider.overrideWithValue(const AsyncData([])),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  const good = EntryStatusTotals(
    pendingCount: 2,
    approvedCount: 1265,
    declinedCount: 0,
    approvedTotalCedis: 2014920.43,
  );
  final failed = AsyncError<EntryStatusTotals>(
    Exception('FAILED_PRECONDITION: The query requires an index.'),
    StackTrace.empty,
  );

  test('pastor: a failed totals query is flagged, not shown as zero', () {
    final c = containerFor('pastor', failed);
    expect(c.read(pastorEntryStatsProvider).totalsFailed, isTrue);
  });

  test('pastor: real totals come through unflagged', () {
    final c = containerFor('pastor', const AsyncData(good));
    final s = c.read(pastorEntryStatsProvider);
    expect(s.totalsFailed, isFalse);
    expect(s.approvedCount, 1265);
    expect(s.totalApprovedCedis, 2014920.43);
  });

  test('staff: a failed totals query is flagged', () {
    final c = containerFor('staff', failed);
    expect(c.read(staffMyEntryStatsProvider).totalsFailed, isTrue);
  });

  test('staff: real totals come through unflagged', () {
    final c = containerFor('staff', const AsyncData(good));
    final s = c.read(staffMyEntryStatsProvider);
    expect(s.totalsFailed, isFalse);
    expect(s.approvedTotalCedis, 2014920.43);
  });
}
