import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import 'bulk_import_session_store.dart';

/// The unfinished import saved for the signed-in user, if there is one.
///
/// Surfaced on Overview so a half-done import is not something you have to
/// remember — an import abandoned halfway is money not yet recorded.
final bulkImportDraftProvider =
    FutureProvider.autoDispose<BulkImportPersistedSession?>((ref) async {
      final idx = await ref.watch(userChurchIndexProvider.future);
      if (idx == null) return null;
      final saved = await BulkImportSessionStore.load(
        uid: idx.uid,
        churchId: idx.churchId,
      );
      if (saved == null || saved.rawRows.isEmpty) return null;
      return saved;
    });
