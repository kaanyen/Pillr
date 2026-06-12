import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/partnership_entry.dart';

/// In-memory entries list UI state so switching shell tabs does not reset filters or loaded rows.
class EntriesListSessionState {
  const EntriesListSessionState({
    this.churchId,
    this.initialized = false,
    this.items = const [],
    this.hasMore = true,
    this.statusSegment = 'all',
    this.newestFirst = true,
    this.filterArmId,
    this.filterPeriodId,
    this.scrollOffset = 0,
  });

  final String? churchId;
  final bool initialized;
  final List<PartnershipEntry> items;
  final bool hasMore;
  final String statusSegment;
  final bool newestFirst;
  final String? filterArmId;
  final String? filterPeriodId;
  final double scrollOffset;

  EntriesListSessionState copyWith({
    String? churchId,
    bool? initialized,
    List<PartnershipEntry>? items,
    bool? hasMore,
    String? statusSegment,
    bool? newestFirst,
    String? filterArmId,
    String? filterPeriodId,
    double? scrollOffset,
    bool clearFilters = false,
  }) {
    return EntriesListSessionState(
      churchId: churchId ?? this.churchId,
      initialized: initialized ?? this.initialized,
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      statusSegment: statusSegment ?? this.statusSegment,
      newestFirst: newestFirst ?? this.newestFirst,
      filterArmId: clearFilters ? null : (filterArmId ?? this.filterArmId),
      filterPeriodId: clearFilters ? null : (filterPeriodId ?? this.filterPeriodId),
      scrollOffset: scrollOffset ?? this.scrollOffset,
    );
  }
}

final entriesListSessionProvider =
    NotifierProvider<EntriesListSessionNotifier, EntriesListSessionState>(
  EntriesListSessionNotifier.new,
);

class EntriesListSessionNotifier extends Notifier<EntriesListSessionState> {
  @override
  EntriesListSessionState build() => const EntriesListSessionState();

  void resetForChurch(String churchId) {
    state = EntriesListSessionState(churchId: churchId);
  }

  void apply({
    required String churchId,
    bool? initialized,
    List<PartnershipEntry>? items,
    bool? hasMore,
    String? statusSegment,
    bool? newestFirst,
    String? filterArmId,
    String? filterPeriodId,
    double? scrollOffset,
    bool clearFilters = false,
  }) {
    if (state.churchId != churchId) {
      state = EntriesListSessionState(churchId: churchId);
    }
    state = state.copyWith(
      churchId: churchId,
      initialized: initialized,
      items: items,
      hasMore: hasMore,
      statusSegment: statusSegment,
      newestFirst: newestFirst,
      filterArmId: filterArmId,
      filterPeriodId: filterPeriodId,
      scrollOffset: scrollOffset,
      clearFilters: clearFilters,
    );
  }
}
