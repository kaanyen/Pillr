import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../common/widgets/pillr_badge.dart';
import '../../../common/widgets/pillr_card.dart';
import '../../../common/widgets/pillr_empty_state.dart';
import '../../../common/widgets/pillr_error_state.dart';
import '../../../common/widgets/pillr_loading_shimmer.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../../core/utils/pdf_report_utils.dart';
import '../../auth/providers/auth_providers.dart';
import '../../church/providers/church_settings_providers.dart';
import '../domain/partnership_entry.dart';
import '../providers/entries_providers.dart';

class PendingApprovalsScreen extends ConsumerWidget {
  const PendingApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingEntriesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pending approvals', style: AppTypography.heading2),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Review entries submitted by staff. Approve or decline with a reason.',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.lg),
          pending.when(
            loading: () => const PillrLoadingShimmer(height: 200),
            error: (e, _) => PillrErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(pendingEntriesProvider),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return const PillrEmptyState(
                  title: 'All caught up',
                  message: 'No pending entries right now.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        final church = ref.read(churchNameProvider) ?? 'Church';
                        final logoUrl = ref.read(churchSettingsProvider).valueOrNull?.logoUrl;
                        final l10n = AppLocalizations.of(context);
                        final profile = ref.read(churchUserProfileProvider).valueOrNull;
                        final email = ref.read(firebaseAuthProvider).currentUser?.email;
                        final exporter =
                            (profile?.fullName.isNotEmpty == true) ? profile!.fullName : (email ?? '—');
                        final when = DateFormat.yMMMd(Localizations.localeOf(context).toString())
                            .add_Hm()
                            .format(DateTime.now());
                        await shareTablePdf(
                          title: 'Pending approvals',
                          subtitle: church,
                          logoUrl: logoUrl,
                          headers: const ['Partner', 'Amount', 'Submitted'],
                          rows: [
                            for (final e in rows)
                              [
                                e.partnerSnapshot['fullName']?.toString() ?? '—',
                                formatCedis(e.amountCedis),
                                e.createdAt.toIso8601String().split('T').first,
                              ],
                          ],
                          filename: 'pillr-pending-approvals.pdf',
                          generatedAtLine: l10n.pdfGeneratedAt(when),
                          exporterLine: l10n.pdfExporter(exporter),
                          footerBrand: l10n.pdfFooterBrand,
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Export PDF'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final e in rows) _EntryCard(entry: e),
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
  const _EntryCard({required this.entry});

  final PartnershipEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: PillrCard(
        child: InkWell(
          onTap: () => context.go('/entries/${entry.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.partnerSnapshot['fullName']?.toString() ?? 'Partner',
                      style: AppTypography.heading3,
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
              Text(formatCedis(entry.amountCedis), style: AppTypography.heading2),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'By ${entry.createdBySnapshot['fullName'] ?? 'Staff'}',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.go('/entries/${entry.id}'),
                  child: const Text('Review'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
