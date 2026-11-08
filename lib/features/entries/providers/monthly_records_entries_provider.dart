import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/domain/user_church_index.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/entries_repository.dart';
import '../domain/partnership_entry.dart';
import '../../../core/errors/plain_error.dart';

class MonthlyRecordsEntriesState {
  const MonthlyRecordsEntriesState({
    this.entries = const [],
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
    this.initialized = false,
  });

  final List<PartnershipEntry> entries;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;
  final bool initialized;

  MonthlyRecordsEntriesState copyWith({
    List<PartnershipEntry>? entries,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    String? error,
    bool? initialized,
    bool clearError = false,
  }) {
    return MonthlyRecordsEntriesState(
      entries: entries ?? this.entries,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      initialized: initialized ?? this.initialized,
    );
  }
}

final monthlyRecordsEntriesProvider =
    NotifierProvider.autoDispose<MonthlyRecordsEntriesNotifier,
        MonthlyRecordsEntriesState>(
  MonthlyRecordsEntriesNotifier.new,
);

class MonthlyRecordsEntriesNotifier
    extends Notifier<MonthlyRecordsEntriesState> {
  static const _pageSize = 200;

  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  String? _loadedForKey;

  @override
  MonthlyRecordsEntriesState build() {
    ref.listen(userChurchIndexProvider, (previous, next) {
      final key = _sessionKey(next.valueOrNull);
      if (key == _loadedForKey) return;
      _loadedForKey = key;
      _cursor = null;
      // `fireImmediately` runs this inside build(), before the notifier has a
      // state. loadPage reads `state`, which Riverpod 3 refuses there ("Tried
      // to read the state of an uninitialized provider"); the throw landed in
      // an unawaited future, so nothing surfaced it and By month sat on its
      // loading skeleton for good. Any state set here would also be
      // overwritten by build()'s own return value. So act once build() has
      // returned — and not at all if the screen has already gone.
      Future.microtask(() {
        if (!ref.mounted || key != _loadedForKey) return;
        if (key == null) {
          state = const MonthlyRecordsEntriesState(
            hasMore: false,
            initialized: true,
          );
          return;
        }
        loadPage(reset: true);
      });
    }, fireImmediately: true);

    return const MonthlyRecordsEntriesState(loading: true);
  }

  String? _sessionKey(UserChurchIndex? idx) =>
      idx == null ? null : '${idx.churchId}:${idx.uid}:${idx.isPastor}';

  Future<void> refresh() => loadPage(reset: true);

  Future<void> loadMore() {
    if (state.loading || state.loadingMore || !state.hasMore) {
      return Future.value();
    }
    return loadPage(reset: false);
  }

  Future<void> loadPage({required bool reset}) async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) {
      state = const MonthlyRecordsEntriesState(
        hasMore: false,
        initialized: true,
      );
      return;
    }

    if (reset) {
      _cursor = null;
      state = MonthlyRecordsEntriesState(
        loading: true,
        loadingMore: false,
        hasMore: true,
        initialized: state.initialized,
      );
    } else {
      state = state.copyWith(loadingMore: true, clearError: true);
    }

    try {
      final repo = EntriesRepository(ref.read(firestoreProvider));
      final page = await repo.fetchEntriesPage(
        idx.churchId,
        allChurchEntries: idx.isPastor,
        createdByUid: idx.isPastor ? null : idx.uid,
        statusFilter: 'approved',
        pageSize: _pageSize,
        startAfter: reset ? null : _cursor,
      );

      _cursor = page.lastDoc;
      state = MonthlyRecordsEntriesState(
        entries: reset ? page.items : [...state.entries, ...page.items],
        loading: false,
        loadingMore: false,
        hasMore: page.hasMore,
        initialized: true,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        error: plainError(e),
        initialized: true,
      );
    }
  }
}
