import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../common/widgets/pillr_badge.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_confirmation_dialog.dart';
import '../../../common/widgets/pillr_surface_card.dart';
import '../../../common/widgets/pillr_empty_state.dart';
import '../../../common/widgets/pillr_error_state.dart';
import '../../../common/widgets/pillr_loading_shimmer.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/pdf_report_utils.dart';
import '../../activity/activity_log_helper.dart';
import '../../auth/providers/auth_providers.dart';
import '../../church/providers/church_settings_providers.dart';
import '../domain/partnership_entry.dart';
import '../providers/entries_providers.dart';

class PendingApprovalsScreen extends ConsumerStatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  ConsumerState<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends ConsumerState<PendingApprovalsScreen> {
  final Set<String> _selectedIds = {};
  bool _approving = false;

  void _pruneSelection(List<PartnershipEntry> rows) {
    final ids = rows.map((e) => e.id).toSet();
    if (_selectedIds.any((id) => !ids.contains(id))) {
      _selectedIds.removeWhere((id) => !ids.contains(id));
    }
  }

  bool _allSelected(List<PartnershipEntry> rows) =>
      rows.isNotEmpty && _selectedIds.length == rows.length;

  void _toggleSelectAll(List<PartnershipEntry> rows) {
    setState(() {
      if (_allSelected(rows)) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(rows.map((e) => e.id));
      }
    });
  }

  void _toggleEntry(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _approveEntries(
    BuildContext context,
    List<PartnershipEntry> targets,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (targets.isEmpty || _approving) return;

    final profile = ref.read(churchUserProfileProvider).valueOrNull;
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (profile == null || idx == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final successTpl = l10n.approvalsApproveSuccess;

    final ok = await showPillrConfirmationDialog(
      context: context,
      title: l10n.approvalsApproveConfirmTitle,
      message: l10n.approvalsApproveConfirmMessage(targets.length),
      confirmLabel: l10n.approvalsApproveConfirmAction,
      cancelLabel: l10n.bulkImportCancel,
      confirmVariant: PillrButtonVariant.primary,
    );
    if (ok != true || !mounted) return;

    setState(() => _approving = true);
    try {
      final repo = ref.read(entriesRepositoryProvider);
      final count = await repo.approveEntries(
        churchId: idx.churchId,
        entries: targets,
        pastor: profile,
      );

      for (final entry in targets) {
        if (entry.status != 'pending') continue;
        await logPillrActivity(
          ref,
          churchId: idx.churchId,
          action: 'entry.approve',
          entityType: 'entry',
          entityId: entry.id,
          metadata: {
            'before': {'status': entry.status},
            'after': {'status': 'approved'},
            'bulkApproval': true,
            'entrySummary': {
              'amountCedis': entry.amountCedis,
              'partnerName': entry.partnerSnapshot['fullName'],
              'memberId': entry.partnerSnapshot['memberId'],
            },
          },
        );
      }

      if (!mounted) return;
      setState(() {
        _approving = false;
        _selectedIds.clear();
      });
      messenger.showSnackBar(
        SnackBar(content: Text(successTpl(count))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _approving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _exportPdf(BuildContext context, List<PartnershipEntry> rows) async {
    final church = ref.read(churchNameProvider) ?? 'Church';
    final logoUrl = ref.read(churchSettingsProvider).valueOrNull?.logoUrl;
    final l10n = AppLocalizations.of(context);
    final profile = ref.read(churchUserProfileProvider).valueOrNull;
    final email = ref.read(firebaseAuthProvider).currentUser?.email;
    final exporter = (profile?.fullName.isNotEmpty == true) ? profile!.fullName : (email ?? '—');
    final formatMoney = ref.read(churchMoneyFormatProvider);
    final when = DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .add_Hm()
        .format(DateTime.now());
    await shareTablePdf(
      title: l10n.titleApprovals,
      subtitle: church,
      logoUrl: logoUrl,
      headers: const ['Partner', 'Amount', 'Submitted'],
      rows: [
        for (final e in rows)
          [
            e.partnerSnapshot['fullName']?.toString() ?? '—',
            formatMoney(e.amountCedis),
            e.createdAt.toIso8601String().split('T').first,
          ],
      ],
      filename: 'pillr-pending-approvals.pdf',
      generatedAtLine: l10n.pdfGeneratedAt(when),
      exporterLine: l10n.pdfExporter(exporter),
      footerBrand: l10n.pdfFooterBrand,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatMoney = ref.watch(churchMoneyFormatProvider);
    final pending = ref.watch(pendingEntriesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.titleApprovals, style: AppTypography.heading),
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.approvalsSubtitle, style: AppTypography.body),
          const SizedBox(height: AppSpacing.lg),
          pending.when(
            loading: () => const PillrLoadingShimmer(height: 200),
            error: (e, _) => PillrErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(pendingEntriesProvider),
            ),
            data: (rows) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final before = _selectedIds.length;
                _pruneSelection(rows);
                if (_selectedIds.length != before) setState(() {});
              });
              if (rows.isEmpty) {
                return PillrEmptyState(
                  title: l10n.approvalsEmptyTitle,
                  message: l10n.approvalsEmptyMessage,
                );
              }

              final selected = rows.where((e) => _selectedIds.contains(e.id)).toList();
              final allSelected = _allSelected(rows);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _approving ? null : () => _exportPdf(context, rows),
                        icon: const Icon(LucideIcons.fileDown),
                        label: Text(l10n.approvalsExportPdf),
                      ),
                      TextButton.icon(
                        onPressed: _approving ? null : () => _toggleSelectAll(rows),
                        icon: Icon(allSelected ? LucideIcons.square : LucideIcons.checkSquare),
                        label: Text(allSelected ? l10n.approvalsClearSelection : l10n.approvalsSelectAll),
                      ),
                      if (_selectedIds.isNotEmpty)
                        Text(
                          l10n.approvalsSelectedCount(_selectedIds.length),
                          style: AppTypography.caption.copyWith(color: AppColors.smoke),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: PillrButton(
                          label: l10n.approvalsApproveSelected,
                          icon: LucideIcons.checkCircle,
                          loading: _approving,
                          onPressed: _approving || selected.isEmpty
                              ? null
                              : () => _approveEntries(context, selected),
                          expanded: true,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: PillrButton(
                          label: l10n.approvalsApproveAll(rows.length),
                          icon: LucideIcons.clipboardCheck,
                          variant: PillrButtonVariant.secondary,
                          loading: _approving,
                          onPressed: _approving ? null : () => _approveEntries(context, rows),
                          expanded: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (var i = 0; i < rows.length; i++)
                    _EntryCard(
                      entry: rows[i],
                      formatMoney: formatMoney,
                      l10n: l10n,
                      selected: _selectedIds.contains(rows[i].id),
                      selectionEnabled: !_approving,
                      onToggleSelected: () => _toggleEntry(rows[i].id),
                    )
                        .animate()
                        .fade(duration: 350.ms, delay: (40 * i).ms)
                        .slideY(begin: 0.04, curve: Curves.easeOutCubic),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.formatMoney,
    required this.l10n,
    required this.selected,
    required this.selectionEnabled,
    required this.onToggleSelected,
  });

  final PartnershipEntry entry;
  final String Function(num) formatMoney;
  final AppLocalizations l10n;
  final bool selected;
  final bool selectionEnabled;
  final VoidCallback onToggleSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: PillrSurfaceCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: selected,
                  onChanged: selectionEnabled ? (_) => onToggleSelected() : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.partnerSnapshot['fullName']?.toString() ?? 'Partner',
                              style: AppTypography.headingSm,
                            ),
                          ),
                          const PillrBadge(label: 'Pending', kind: PillrBadgeKind.pending, compact: true),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '${entry.armSnapshot['name'] ?? '—'} · ${entry.periodSnapshot['name'] ?? '—'}',
                        style: AppTypography.caption,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(formatMoney(entry.amountCedis), style: AppTypography.heading),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        l10n.approvalsSubmittedBy(
                          entry.createdBySnapshot['fullName']?.toString() ?? 'Staff',
                        ),
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: PillrButton(
                label: l10n.approvalsReview,
                icon: LucideIcons.arrowRight,
                variant: PillrButtonVariant.secondary,
                onPressed: () => context.go('/entries/${entry.id}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
