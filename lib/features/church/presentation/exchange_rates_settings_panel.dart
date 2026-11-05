import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../../design/seline.dart';
import '../../activity/activity_log_helper.dart';
import '../../auth/providers/auth_providers.dart';
import '../../entries/providers/entries_providers.dart';
import '../domain/exchange_rates.dart';
import '../providers/church_settings_providers.dart';

/// Exchange rates → GHS. Pastor, admin, and staff may save; only a pastor
/// may rewrite already-recorded foreign entries.
class ExchangeRatesSettingsPanel extends ConsumerStatefulWidget {
  const ExchangeRatesSettingsPanel({
    super.key,
    required this.churchId,
    required this.initialRates,
    this.bare = false,
  });

  final String churchId;
  final ChurchExchangeRates initialRates;

  /// Without its own card, for Settings' two-column sections.
  final bool bare;

  @override
  ConsumerState<ExchangeRatesSettingsPanel> createState() =>
      _ExchangeRatesSettingsPanelState();
}

class _ExchangeRatesSettingsPanelState
    extends ConsumerState<ExchangeRatesSettingsPanel> {
  late final TextEditingController _usd;
  late final TextEditingController _eur;
  late final TextEditingController _gbp;
  bool _busy = false;
  bool _recalculating = false;

  @override
  void initState() {
    super.initState();
    _usd = TextEditingController(
      text: _formatRate(widget.initialRates.ratesToBase[SelectableCurrency.usd]),
    );
    _eur = TextEditingController(
      text: _formatRate(widget.initialRates.ratesToBase[SelectableCurrency.eur]),
    );
    _gbp = TextEditingController(
      text: _formatRate(widget.initialRates.ratesToBase[SelectableCurrency.gbp]),
    );
  }

  @override
  void dispose() {
    _usd.dispose();
    _eur.dispose();
    _gbp.dispose();
    super.dispose();
  }

  String _formatRate(double? rate) =>
      rate == null ? '' : rate.toStringAsFixed(2);

  double? _parseRate(String raw) {
    final v = double.tryParse(raw.trim().replaceAll(',', ''));
    if (v == null || v <= 0) return null;
    return v;
  }

  Future<void> _recalculate() async {
    final usd = _parseRate(_usd.text);
    final eur = _parseRate(_eur.text);
    final gbp = _parseRate(_gbp.text);
    if (usd == null || eur == null || gbp == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save valid rates before recalculating.')),
        );
      }
      return;
    }

    final rates = ChurchExchangeRates(
      ratesToBase: {
        SelectableCurrency.usd: usd,
        SelectableCurrency.eur: eur,
        SelectableCurrency.gbp: gbp,
      },
    );

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => SelDialog(
        title: 'Recalculate foreign entries?',
        subtitle:
            'Every entry saved in USD, EUR, or GBP will be converted again '
            'using the rates above. Original amounts stay the same; only the '
            'GHS total and stored rate update. Church totals will adjust.',
        actions: [
          SelButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          SelButton.cyan(
            label: 'Recalculate',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        child: const SizedBox.shrink(),
      ),
    );
    if (proceed != true || !mounted) return;

    setState(() => _recalculating = true);
    try {
      await ref.read(churchSettingsRepositoryProvider).updateExchangeRates(
            churchId: widget.churchId,
            rates: rates,
          );
      final result = await ref
          .read(entriesRepositoryProvider)
          .recalculateForeignEntries(
            churchId: widget.churchId,
            rates: rates,
          );
      ref.invalidate(rankingEntriesProvider);
      invalidateEntryDerivedData(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.scanned == 0
                  ? 'No foreign-currency entries found.'
                  : 'Updated ${result.updated} of ${result.scanned} foreign entries '
                      '(${result.unchanged} already matched).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _recalculating = false);
    }
  }

  Future<void> _save() async {
    final usd = _parseRate(_usd.text);
    final eur = _parseRate(_eur.text);
    final gbp = _parseRate(_gbp.text);
    if (usd == null || eur == null || gbp == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a positive rate for each currency.')),
        );
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(churchSettingsRepositoryProvider).updateExchangeRates(
            churchId: widget.churchId,
            rates: ChurchExchangeRates(
              ratesToBase: {
                SelectableCurrency.usd: usd,
                SelectableCurrency.eur: eur,
                SelectableCurrency.gbp: gbp,
              },
            ),
          );
      await logPillrActivity(
        ref,
        churchId: widget.churchId,
        action: 'settings.exchange_rates',
        entityType: 'church',
        entityId: widget.churchId,
        entitySnapshot: {
          'USD': usd,
          'EUR': eur,
          'GBP': gbp,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exchange rates saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRecalculate =
        ref.watch(userChurchIndexProvider).valueOrNull?.isPastor ?? false;
    return SelPanel(
      bare: widget.bare,
      title: 'Exchange rates',
      subtitle:
          'Base currency is Ghana cedi (${BaseCurrency.code}). '
          'Rates convert foreign giving to ${BaseCurrency.symbol} when entries are saved.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelField(
            controller: _usd,
            label: '1 USD → GHS',
            hint: '12.50',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: SelSpace.x4),
          SelField(
            controller: _eur,
            label: '1 EUR → GHS',
            hint: '13.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: SelSpace.x4),
          SelField(
            controller: _gbp,
            label: '1 GBP → GHS',
            hint: '16.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: SelSpace.x6),
          SelButton.cyan(
            label: 'Save rates',
            loading: _busy,
            onPressed: _busy || _recalculating ? null : _save,
          ),
          if (canRecalculate) ...[
            const SizedBox(height: SelSpace.x3),
            SelButton(
              label: 'Recalculate foreign entries',
              loading: _recalculating,
              onPressed: _busy || _recalculating ? null : _recalculate,
            ),
            const SizedBox(height: SelSpace.x2),
            Text(
              'Use after changing rates. Reconverts saved USD/EUR/GBP entries to GHS.',
              style: SelType.small,
            ),
          ],
        ],
      ),
    );
  }
}
