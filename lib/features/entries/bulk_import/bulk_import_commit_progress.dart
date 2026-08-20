import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

enum BulkImportCommitPhase { idle, running, done, failed }

class BulkImportCommitProgressState {
  const BulkImportCommitProgressState({
    this.phase = BulkImportCommitPhase.idle,
    this.current = 0,
    this.total = 0,
    this.message,
    this.dismissed = false,
    this.errorMessage,
  });

  final BulkImportCommitPhase phase;
  final int current;
  final int total;
  final String? message;
  final bool dismissed;
  final String? errorMessage;

  bool get isActive =>
      phase == BulkImportCommitPhase.running || phase == BulkImportCommitPhase.done;

  BulkImportCommitProgressState copyWith({
    BulkImportCommitPhase? phase,
    int? current,
    int? total,
    String? message,
    bool? dismissed,
    String? errorMessage,
    bool clearError = false,
  }) {
    return BulkImportCommitProgressState(
      phase: phase ?? this.phase,
      current: current ?? this.current,
      total: total ?? this.total,
      message: message ?? this.message,
      dismissed: dismissed ?? this.dismissed,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final bulkImportCommitProgressProvider =
    NotifierProvider<BulkImportCommitProgressNotifier, BulkImportCommitProgressState>(
  BulkImportCommitProgressNotifier.new,
);

class BulkImportCommitProgressNotifier extends Notifier<BulkImportCommitProgressState> {
  @override
  BulkImportCommitProgressState build() => const BulkImportCommitProgressState();

  void start(int total, String message) {
    state = BulkImportCommitProgressState(
      phase: BulkImportCommitPhase.running,
      current: 0,
      total: total,
      message: message,
      dismissed: false,
    );
  }

  void update(int current, String message) {
    if (state.phase != BulkImportCommitPhase.running) return;
    state = state.copyWith(current: current, message: message);
  }

  void dismiss() {
    if (!state.isActive) return;
    state = state.copyWith(dismissed: true);
  }

  void complete() {
    state = state.copyWith(
      phase: BulkImportCommitPhase.done,
      current: state.total,
    );
  }

  void fail(String message) {
    state = BulkImportCommitProgressState(
      phase: BulkImportCommitPhase.failed,
      errorMessage: message,
      dismissed: state.dismissed,
    );
  }

  void reset() {
    state = const BulkImportCommitProgressState();
  }
}

/// Global overlay for bulk import commit progress (center panel or bottom-right chip).
class BulkImportCommitProgressOverlay extends ConsumerWidget {
  const BulkImportCommitProgressOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(bulkImportCommitProgressProvider);
    return Stack(
      children: [
        child,
        if (progress.phase == BulkImportCommitPhase.running && !progress.dismissed)
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.ink.withValues(alpha: 0.4),
              child: Center(
                child: _BulkImportProgressCard(
                  progress: progress,
                  onDismiss: () => ref.read(bulkImportCommitProgressProvider.notifier).dismiss(),
                  compact: false,
                ),
              ),
            ),
          ),
        if (progress.isActive && progress.dismissed)
          Positioned(
            right: AppSpacing.lg,
            bottom: AppSpacing.lg,
            child: _BulkImportProgressCard(
              progress: progress,
              onDismiss: progress.phase == BulkImportCommitPhase.running
                  ? () => ref.read(bulkImportCommitProgressProvider.notifier).dismiss()
                  : () => ref.read(bulkImportCommitProgressProvider.notifier).reset(),
              compact: true,
            ),
          ),
      ],
    );
  }
}

class _BulkImportProgressCard extends StatelessWidget {
  const _BulkImportProgressCard({
    required this.progress,
    required this.onDismiss,
    required this.compact,
  });

  final BulkImportCommitProgressState progress;
  final VoidCallback onDismiss;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fraction = progress.total > 0 ? progress.current / progress.total : 0.0;
    final title = progress.phase == BulkImportCommitPhase.done
        ? l10n.bulkImportCommitDoneTitle
        : l10n.bulkImportCommitProgressTitle;

    return Material(
      elevation: 0,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      color: AppColors.paper,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 320 : 400),
        child: Padding(
          padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    progress.phase == BulkImportCommitPhase.done
                        ? LucideIcons.checkCircle
                        : LucideIcons.loader,
                    size: 20,
                    color: AppColors.charcoal,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(title, style: AppTypography.label)),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: onDismiss,
                    tooltip: l10n.bulkImportCommitDismiss,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (progress.message != null)
                Text(
                  progress.message!,
                  style: AppTypography.caption.copyWith(color: AppColors.smoke),
                ),
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(
                value: progress.phase == BulkImportCommitPhase.done ? 1 : fraction.clamp(0, 1),
                minHeight: 6,
                borderRadius: BorderRadius.circular(AppRadius.bar),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.bulkImportCommitProgressCount(progress.current, progress.total),
                style: AppTypography.caption,
                textAlign: TextAlign.end,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
