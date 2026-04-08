import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/pillr_text_field.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../auth/providers/auth_providers.dart';
import '../../entries/domain/partnership_entry.dart';
import '../../entries/providers/entries_providers.dart';
import '../../partners/domain/partner.dart';
import '../../partners/providers/partners_providers.dart';

/// Pastor-only global search (partners + entries) — §16.4.8.
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _q = TextEditingController();
  bool _loading = false;
  List<Partner> _partners = [];
  List<PartnershipEntry> _entries = [];
  String? _error;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null || !idx.isPastor) return;
    final query = _q.text.trim();
    if (query.length < 2) {
      setState(() {
        _error = 'Enter at least 2 characters.';
        _partners = [];
        _entries = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pRepo = ref.read(partnersRepositoryProvider);
      final eRepo = ref.read(entriesRepositoryProvider);
      final partners = await pRepo.searchPartners(idx.churchId, query);
      final entryPage = await eRepo.fetchEntriesPage(
        idx.churchId,
        allChurchEntries: true,
        pageSize: 80,
      );
      final qLower = query.toLowerCase();
      final entries = entryPage.items.where((e) {
        final name = e.partnerSnapshot['fullName']?.toString().toLowerCase() ?? '';
        final status = e.status.toLowerCase();
        return name.contains(qLower) || status.contains(qLower);
      }).toList();
      if (!mounted) return;
      setState(() {
        _partners = partners;
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    if (idx == null || !idx.isPastor) {
      return const Center(child: Text('Search is available to pastors only.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Search', style: AppTypography.heading2),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Find partners and recent entries by name or keyword.',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: PillrTextField(
                  controller: _q,
                  label: 'Query',
                  hint: 'Partner name, entry keyword…',
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton(
                onPressed: _loading ? null : _run,
                child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Search'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: AppTypography.caption.copyWith(color: Colors.red)),
          ],
          const SizedBox(height: AppSpacing.xl),
          Text('Partners', style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          if (_partners.isEmpty)
            Text('No partner matches.', style: AppTypography.caption)
          else
            ..._partners.map(
              (p) => ListTile(
                title: Text(p.fullName),
                subtitle: Text(p.displayLabel),
                onTap: () => context.go('/partners/${p.id}'),
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          Text('Entries', style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          if (_entries.isEmpty)
            Text('No entry matches in the latest batch.', style: AppTypography.caption)
          else
            ..._entries.map(
              (e) => ListTile(
                title: Text(e.partnerSnapshot['fullName']?.toString() ?? '—'),
                subtitle: Text('${formatCedis(e.amountCedis)} · ${e.status}'),
                onTap: () => context.go('/entries/${e.id}'),
              ),
            ),
        ],
      ),
    );
  }
}
