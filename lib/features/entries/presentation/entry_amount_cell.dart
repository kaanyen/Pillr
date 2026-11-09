import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../design/seline.dart';
import '../domain/partnership_entry.dart';

/// GHS amount with a subtle globe when the entry was recorded in foreign currency.
///
/// Hover (or long-press on mobile) reveals the original amount and code.
class EntryAmountCell extends StatelessWidget {
  const EntryAmountCell({
    super.key,
    required this.entry,
    required this.formattedAmount,
    this.tone = SelTone.neutral,
    this.strong = true,
  });

  final PartnershipEntry entry;
  final String formattedAmount;
  final SelTone tone;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final amount = SelCell.numeric(
      formattedAmount,
      strong: strong,
      tone: tone,
    );
    if (!entry.hasForeignSource) return amount;

    final hint =
        'Recorded as ${entry.displaySourceAmount.toStringAsFixed(2)} '
        '${entry.displaySourceCurrency}';

    return Tooltip(
      message: hint,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(child: amount),
          const SizedBox(width: 4),
          Semantics(
            label: hint,
            child: const Icon(
              LucideIcons.globe,
              size: 11,
              color: Sel.ash,
            ),
          ),
        ],
      ),
    );
  }
}
