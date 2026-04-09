import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../../core/utils/pdf_report_utils.dart';
import '../../church/providers/church_settings_providers.dart';
import '../../arms/domain/partnership_arm.dart';
import '../../arms/providers/arms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../entries/providers/entries_providers.dart';
import '../../periods/domain/partnership_period.dart';
import '../../periods/providers/periods_providers.dart';
import '../leaderboard_models.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  String? _periodId;
  String? _armId;

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(entriesListProvider);
    final periodsAsync = ref.watch(periodsStreamProvider);
    final armsAsync = ref.watch(armsStreamProvider);

    return entriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (entries) {
        return periodsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (periods) {
            return armsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (arms) {
                final rows = LeaderboardRow.fromEntries(
                  entries,
                  periodId: _periodId,
                  armId: _armId,
                );
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Leaderboard', style: AppTypography.heading2),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Ranked by approved giving. Updates live as entries change.',
                        style: AppTypography.body,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: rows.isEmpty
                              ? null
                              : () async {
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
                                    title: 'Leaderboard',
                                    subtitle: church,
                                    logoUrl: logoUrl,
                                    headers: const ['Rank', 'Partner', 'Approved ₵'],
                                    rows: [
                                      for (final r in rows)
                                        [
                                          r.rank.toString(),
                                          r.partnerName,
                                          formatCedis(r.totalCedis),
                                        ],
                                    ],
                                    filename: 'pillr-leaderboard.pdf',
                                    generatedAtLine: l10n.pdfGeneratedAt(when),
                                    exporterLine: l10n.pdfExporter(exporter),
                                    footerBrand: l10n.pdfFooterBrand,
                                  );
                                },
                          icon: const Icon(LucideIcons.fileDown),
                          label: const Text('Export PDF'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 240,
                            child: _PeriodDropdown(
                              periods: periods,
                              value: _periodId,
                              onChanged: (v) => setState(() => _periodId = v),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: _ArmDropdown(
                              arms: arms,
                              value: _armId,
                              onChanged: (v) => setState(() => _armId = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (rows.isEmpty)
                        Text('No approved entries for this filter.', style: AppTypography.body)
                      else
                        ...rows.map((r) => _LeaderTile(row: r)),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PeriodDropdown extends StatelessWidget {
  const _PeriodDropdown({
    required this.periods,
    required this.value,
    required this.onChanged,
  });

  final List<PartnershipPeriod> periods;
  final String? value;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      key: ValueKey('period-$value'),
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Period',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('All periods')),
        for (final p in periods)
          DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
      ],
      onChanged: onChanged,
    );
  }
}

class _ArmDropdown extends StatelessWidget {
  const _ArmDropdown({
    required this.arms,
    required this.value,
    required this.onChanged,
  });

  final List<PartnershipArm> arms;
  final String? value;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      key: ValueKey('arm-$value'),
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Arm',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('All arms')),
        for (final a in arms)
          DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
      ],
      onChanged: onChanged,
    );
  }
}

class _LeaderTile extends StatelessWidget {
  const _LeaderTile({required this.row});

  final LeaderboardRow row;

  @override
  Widget build(BuildContext context) {
    final medal = switch (row.rank) {
      1 => Icon(LucideIcons.trophy, color: AppColors.warningColor, size: 28),
      2 => Icon(LucideIcons.trophy, color: AppColors.gray400, size: 26),
      3 => Icon(LucideIcons.trophy, color: AppColors.progressOrange, size: 24),
      _ => SizedBox(
          width: 28,
          child: Text('${row.rank}', style: AppTypography.heading3, textAlign: TextAlign.center),
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: () => context.go('/partners/${row.partnerId}'),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            child: Row(
              children: [
                SizedBox(width: 40, child: medal),
                Expanded(
                  child: Text(
                    row.partnerName,
                    style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  formatCedis(row.totalCedis),
                  style: AppTypography.body.copyWith(color: AppColors.primaryColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
