import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../design/seline.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/church/providers/church_settings_providers.dart';
import '../../features/entries/providers/entries_providers.dart';

/// Confirmation after recording an entry.
///
/// Deliberately understated: a hairline check, the figure, and the two things
/// someone actually wants next. A full-screen celebration would be the loudest
/// moment in a product about careful bookkeeping.
class EntrySuccessScreen extends ConsumerWidget {
  const EntrySuccessScreen({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(churchMoneyFormatProvider);
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final entry = ref.watch(entryDetailProvider(entryId)).valueOrNull;

    final partner = entry?.partnerSnapshot['fullName']?.toString() ?? '';
    final pending = entry?.status == 'pending';

    return SelPageBody(
      maxWidth: 520,
      children: [
        const SizedBox(height: SelSpace.x16),
        Center(
          child: Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: Sel.card,
              borderRadius: BorderRadius.circular(SelRadius.pill),
              border: Border.all(color: Sel.border),
              boxShadow: SelShadow.card,
            ),
            child: const Icon(LucideIcons.check, size: 18, color: Sel.ink),
          ),
        ),
        const SizedBox(height: SelSpace.x6),
        Text(
          'Entry recorded',
          style: SelType.title,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SelSpace.x3),
        Text(
          entry == null
              ? 'Your entry has been saved.'
              : pending
                  ? '${money(entry.amountCedis)} for $partner is now with a pastor for review.'
                  : '${money(entry.amountCedis)} for $partner has been added to your church totals.',
          style: SelType.lead,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SelSpace.x8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SelButton(
              label: 'View entry',
              onPressed: () => context.go('/entries/$entryId'),
            ),
            const SizedBox(width: SelSpace.x2),
            if (idx?.isStaff == true || idx?.isPastor == true)
              SelButton.cyan(
                label: 'Record another',
                icon: LucideIcons.plus,
                onPressed: () => context.go('/entries/new'),
              ),
          ],
        ),
        const SizedBox(height: SelSpace.x4),
        Center(
          child: SelButton(
            label: 'Back to queue',
            kind: SelButtonKind.quiet,
            onPressed: () => context.go('/queue'),
          ),
        ),
      ],
    );
  }
}
