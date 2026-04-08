import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../common/widgets/pillr_button.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/currency_utils.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/entries_providers.dart';

/// Shown after creating a new entry — clear next steps (plan: dedicated success screen).
class EntryCreatedSuccessScreen extends ConsumerWidget {
  const EntryCreatedSuccessScreen({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final entryAsync = idx == null
        ? const AsyncValue.loading()
        : ref.watch(entryDetailProvider(entryId));

    final reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    Duration ms(int m) => reducedMotion ? Duration.zero : Duration(milliseconds: m);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: entryAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('$e', style: AppTypography.body),
            data: (entry) {
              if (entry == null) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(l10n.entryNotFound, style: AppTypography.heading3),
                    const SizedBox(height: AppSpacing.md),
                    PillrButton(
                      label: l10n.entryBackToEntries,
                      onPressed: () => context.go('/entries'),
                      variant: PillrButtonVariant.secondary,
                    ),
                  ],
                );
              }
              final partner = entry.partnerSnapshot['fullName']?.toString() ?? '—';
              final amount = formatCedis(entry.amountCedis);
              final period = entry.periodSnapshot['name']?.toString() ?? '';
              final arm = entry.armSnapshot['name']?.toString() ?? '';

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 72,
                    color: AppColors.successColor,
                  )
                      .animate()
                      .scale(
                        duration: ms(350),
                        curve: Curves.easeOutBack,
                        begin: const Offset(0.85, 0.85),
                        end: const Offset(1, 1),
                      )
                      .fadeIn(duration: ms(280)),
                  SizedBox(height: AppSpacing.lg).animate().fadeIn(delay: ms(100)),
                  Text(
                    l10n.entrySubmittedTitle,
                    textAlign: TextAlign.center,
                    style: AppTypography.heading2,
                  ).animate().fadeIn(duration: ms(220), delay: ms(120)).slideY(begin: 0.08, end: 0),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '$partner · $amount',
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                  ).animate().fadeIn(duration: ms(220), delay: ms(180)).slideY(begin: 0.06, end: 0),
                  if (period.isNotEmpty || arm.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        [period, arm].where((s) => s.isNotEmpty).join(' · '),
                        textAlign: TextAlign.center,
                        style: AppTypography.caption,
                      ),
                    ).animate().fadeIn(duration: ms(200), delay: ms(220)),
                  const SizedBox(height: AppSpacing.xl),
                  PillrButton(
                    label: l10n.entrySuccessViewEntry,
                    icon: Icons.visibility_outlined,
                    onPressed: () => context.go('/entries/$entryId'),
                    variant: PillrButtonVariant.primary,
                  ).animate().fadeIn(duration: ms(200), delay: ms(260)).slideY(begin: 0.05, end: 0),
                  const SizedBox(height: AppSpacing.sm),
                  PillrButton(
                    label: l10n.entrySuccessAddAnother,
                    icon: Icons.add,
                    onPressed: () => context.go('/entries/new'),
                    variant: PillrButtonVariant.secondary,
                  ).animate().fadeIn(duration: ms(200), delay: ms(300)).slideY(begin: 0.05, end: 0),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: () => context.go('/entries'),
                    child: Text(l10n.entryBackToEntries),
                  ).animate().fadeIn(duration: ms(180), delay: ms(340)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
