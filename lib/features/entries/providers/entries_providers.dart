import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/entries_repository.dart';
import '../domain/partnership_entry.dart';

final entriesRepositoryProvider = Provider<EntriesRepository>((ref) {
  return EntriesRepository(ref.watch(firestoreProvider));
});

/// Pastor: all entries. Staff: own entries only.
final entriesListProvider = StreamProvider.autoDispose<List<PartnershipEntry>>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value([]);
  final repo = ref.watch(entriesRepositoryProvider);
  if (idx.isPastor) return repo.watchAllEntries(idx.churchId);
  return repo.watchMyEntries(idx.churchId, idx.uid);
});

final pendingEntriesProvider = StreamProvider.autoDispose<List<PartnershipEntry>>((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null || !idx.isPastor) return Stream.value([]);
  return ref.watch(entriesRepositoryProvider).watchPendingEntries(idx.churchId);
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
