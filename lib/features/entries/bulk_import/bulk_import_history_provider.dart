import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../auth/providers/auth_providers.dart';
import 'bulk_import_batches.dart';

/// The full import history, a page at a time.
///
/// `recentImportBatchesProvider` streams the last five for the import screen's
/// own footer. This is the archive behind the Imports view: a church that has
/// been importing weekly for two years has hundreds, and none of them need to
/// be live — an import is a thing that happened, not a thing that changes.
class ImportHistoryState {
  const ImportHistoryState({
    this.batches = const [],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<BulkImportBatch> batches;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;

  ImportHistoryState copyWith({
    List<BulkImportBatch>? batches,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return ImportHistoryState(
      batches: batches ?? this.batches,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final importHistoryProvider =
    NotifierProvider.autoDispose<ImportHistoryNotifier, ImportHistoryState>(
  ImportHistoryNotifier.new,
);

class ImportHistoryNotifier extends Notifier<ImportHistoryState> {
  static const _pageSize = 25;
  DocumentSnapshot<Map<String, dynamic>>? _cursor;

  @override
  ImportHistoryState build() {
    Future.microtask(() => load(reset: true));
    return const ImportHistoryState();
  }

  Future<void> refresh() => load(reset: true);

  Future<void> loadMore() {
    if (state.loading || state.loadingMore || !state.hasMore) {
      return Future.value();
    }
    return load(reset: false);
  }

  Future<void> load({required bool reset}) async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) {
      state = const ImportHistoryState(loading: false, hasMore: false);
      return;
    }

    if (reset) {
      _cursor = null;
      state = const ImportHistoryState(loading: true);
    } else {
      state = state.copyWith(loadingMore: true, clearError: true);
    }

    try {
      final page = await ref.read(bulkImportBatchRepositoryProvider).fetchPage(
            idx.churchId,
            pageSize: _pageSize,
            startAfter: reset ? null : _cursor,
          );
      _cursor = page.lastDoc;
      state = ImportHistoryState(
        batches: reset ? page.items : [...state.batches, ...page.items],
        loading: false,
        loadingMore: false,
        hasMore: page.hasMore,
      );
    } catch (e) {
      state = state.copyWith(loading: false, loadingMore: false, error: '$e');
    }
  }
}
