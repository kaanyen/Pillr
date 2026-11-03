import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../core/navigation/panel_flows.dart';
import '../../core/notifications/sel_notice.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/entry_duplicate_utils.dart';
import '../../core/utils/money.dart';
import '../../design/seline.dart';
import '../../features/church/domain/exchange_rates.dart';
import '../../features/church/providers/church_settings_providers.dart';
import '../../features/activity/activity_log_helper.dart';
import '../../features/arms/domain/partnership_arm.dart';
import '../../features/arms/providers/arms_providers.dart';
import '../../features/auth/domain/church_user.dart';
import '../../features/auth/domain/user_church_index.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/partners/domain/partner.dart';
import '../../features/periods/domain/partnership_period.dart';
import '../../features/periods/providers/periods_providers.dart';
import '../../features/entries/domain/partnership_entry.dart';
import '../../features/entries/providers/entries_providers.dart';

Map<String, dynamic> _entryValuesForActivityLog(PartnershipEntry e) => {
  'partnerId': e.partnerId,
  'partnerName': e.partnerSnapshot['fullName'],
  'memberId': e.partnerSnapshot['memberId'],
  'amountCedis': e.amountCedis,
  'partnershipArmId': e.partnershipArmId,
  'armName': e.armSnapshot['name'],
  'partnershipPeriodId': e.partnershipPeriodId,
  'periodName': e.periodSnapshot['name'],
  'status': e.status,
  'notes': e.notes,
  'dateGiven': e.dateGiven.toIso8601String(),
};

Map<String, dynamic> _afterEntryValues({
  required Partner partner,
  required PartnershipArm arm,
  required PartnershipPeriod period,
  required double amount,
  required DateTime dateGiven,
  required String? notes,
  required String status,
}) => {
  'partnerId': partner.id,
  'partnerName': partner.fullName,
  'memberId': partner.memberId,
  'amountCedis': amount,
  'partnershipArmId': arm.id,
  'armName': arm.name,
  'partnershipPeriodId': period.id,
  'periodName': period.name,
  'status': status,
  'notes': notes,
  'dateGiven': dateGiven.toIso8601String(),
};

/// Create a new partnership entry, or edit an existing one (`entryId` set).
class EntryFormScreen extends ConsumerStatefulWidget {
  const EntryFormScreen({super.key, this.entryId, this.embedded = false});

  /// When non-null, loads [entryId] and saves via staff/pastor update.
  final String? entryId;

  /// Rendered inside a side sheet — no page chrome, closes on save.
  final bool embedded;

  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends ConsumerState<EntryFormScreen> {
  Partner? _partner;
  PartnershipArm? _arm;
  PartnershipPeriod? _period;
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String _sourceCurrency = SelectableCurrency.ghs;
  DateTime _dateGiven = DateTime.now();
  bool _loading = false;
  String? _error;
  bool _seeded = false;
  bool _showMore = false;

  bool get _isEdit => widget.entryId != null;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(EntryFormScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entryId != widget.entryId) {
      _seeded = false;
    }
  }

  void _seedFromEntry(
    PartnershipEntry entry,
    List<PartnershipArm> arms,
    List<PartnershipPeriod> periods,
  ) {
    _partner = Partner(
      id: entry.partnerId,
      churchId: entry.churchId,
      memberId: entry.partnerSnapshot['memberId'] as String? ?? '',
      fullName: entry.partnerSnapshot['fullName'] as String? ?? '',
      fellowship: entry.partnerSnapshot['fellowship'] as String? ?? '',
      email: entry.partnerSnapshot['email'] as String?,
      phone: entry.partnerSnapshot['phone'] as String?,
      isActive: true,
      totalApprovedAmount: 0,
      entryCount: 0,
      createdBy: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    for (final a in arms) {
      if (a.id == entry.partnershipArmId) _arm = a;
    }
    for (final p in periods) {
      if (p.id == entry.partnershipPeriodId) _period = p;
    }
    _amount.text = _formatAmount(entry.displaySourceAmount);
    _sourceCurrency = entry.displaySourceCurrency;
    _notes.text = entry.notes ?? '';
    _dateGiven = entry.dateGiven;
  }

  String _formatAmount(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toString();
  }

  List<PartnershipArm> _armsForForm(
    PartnershipEntry? entry,
    List<PartnershipArm> all,
  ) {
    if (!_isEdit || entry == null) {
      return all.where((a) => a.isActive).toList();
    }
    return all
        .where((a) => a.isActive || a.id == entry.partnershipArmId)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;

    if (_isEdit) {
      final entryAsync = ref.watch(entryDetailProvider(widget.entryId!));
      final armsAsync = ref.watch(armsStreamProvider);
      final periodsAsync = ref.watch(periodsStreamProvider);
      return entryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (entry) {
          if (entry == null) {
            return Center(
              child: TextButton(
                onPressed: () => context.go('/queue'),
                child: const Text('Back to entries'),
              ),
            );
          }
          return armsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (armList) => periodsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (periodList) {
                if (!_seeded) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || _seeded) return;
                    _seedFromEntry(entry, armList, periodList);
                    _showMore =
                        _notes.text.trim().isNotEmpty ||
                        _sourceCurrency != SelectableCurrency.ghs;
                    setState(() => _seeded = true);
                  });
                }
                return _buildForm(
                  context,
                  idx: idx,
                  profile: profile,
                  churchId: idx?.churchId,
                  uid: idx?.uid,
                  armList: armList,
                  periodList: periodList,
                  entry: entry,
                );
              },
            ),
          );
        },
      );
    }

    final arms = ref.watch(armsStreamProvider);
    final active = ref.watch(activePeriodProvider);
    _period ??= active;

    return arms.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (armList) => _buildForm(
        context,
        idx: idx,
        profile: profile,
        churchId: idx?.churchId,
        uid: idx?.uid,
        armList: armList,
        periodList: ref.watch(periodsStreamProvider).valueOrNull ?? [],
        entry: null,
        activePeriodFallback: active,
      ),
    );
  }

  Widget _buildForm(
    BuildContext context, {
    required UserChurchIndex? idx,
    required ChurchUser? profile,
    required String? churchId,
    required String? uid,
    required List<PartnershipArm> armList,
    required List<PartnershipPeriod> periodList,
    required PartnershipEntry? entry,
    PartnershipPeriod? activePeriodFallback,
  }) {
    final arms = _armsForForm(entry, armList);
    final period = _period ?? activePeriodFallback;
    final money = ref.watch(churchMoneyFormatProvider);

    return SelPageBody(
      maxWidth: widget.embedded ? double.infinity : 640,
      children: [
        if (!widget.embedded)
          SelPageTitle(
            title: _isEdit ? 'Edit entry' : 'Record a ',
            highlight: _isEdit ? null : 'gift',
            subtitle: _isEdit
                ? 'Changes are re-recorded in the activity log.'
                : 'Who gave, how much, and toward what.',
          ),
        if (_error != null) ...[
          SelCard(
            lift: SelLift.flat,
            padding: const EdgeInsets.symmetric(
              horizontal: SelSpace.x4,
              vertical: SelSpace.x3,
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.alertCircle, size: 14, color: Sel.ink),
                const SizedBox(width: SelSpace.x2),
                Expanded(
                  child: Text(
                    _error!,
                    style: SelType.bodySm.copyWith(color: Sel.ink),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SelSpace.x4),
        ],

        SelPanel(
          title: 'Partner',
          subtitle: 'Who this gift is from.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PartnerTile(
                partner: _partner,
                onTap: churchId == null || uid == null
                    ? null
                    : () => _pickPartner(context, churchId, uid),
              ),
            ],
          ),
        ),

        const SizedBox(height: SelSpace.x4),

        SelPanel(
          title: 'Partnership details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main arm first; if it has sub-arms, which part of it. The
              // entry keeps its exact arm, but everywhere outside this form
              // and Configuration it shows under the main arm.
              Builder(builder: (context) {
                final tree = ref.watch(armTreeProvider);
                final mainId = _arm == null ? null : tree.shownArmIdOf(_arm!.id);
                final subs = mainId == null
                    ? const <PartnershipArm>[]
                    : [
                        for (final c in tree.childrenOf(mainId))
                          if (arms.any((a) => a.id == c.id)) c,
                      ];
                final mainName = mainId == null ? '' : tree.byId(mainId)?.name ?? '';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelSelect<String>(
                      value: mainId,
                      label: 'Partnership arm',
                      hint: Text('Select an arm', style: SelType.bodyMuted),
                      onChanged: (v) => setState(() {
                        _arm = arms.where((a) => a.id == v).firstOrNull ??
                            (v == null ? null : tree.byId(v));
                      }),
                      items: [
                        for (final m in tree.mains)
                          if (arms.any((a) => a.id == m.id))
                            DropdownMenuItem(value: m.id, child: Text(m.name)),
                      ],
                    ),
                    if (subs.isNotEmpty) ...[
                      const SizedBox(height: SelSpace.x4),
                      SelSelect<String>(
                        value: _arm?.id,
                        label: 'Which part of $mainName?',
                        onChanged: (v) => setState(() {
                          _arm = arms.where((a) => a.id == v).firstOrNull ?? _arm;
                        }),
                        items: [
                          DropdownMenuItem(
                            value: mainId,
                            child: Text('$mainName (general)'),
                          ),
                          for (final c in subs)
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                        ],
                      ),
                    ],
                  ],
                );
              }),
              const SizedBox(height: SelSpace.x4),
              if (_isEdit)
                SelSelect<String>(
                  value: period?.id,
                  label: 'Period',
                  onChanged: (v) => setState(() {
                    _period = periodList.where((p) => p.id == v).firstOrNull;
                  }),
                  items: [
                    for (final p in periodList)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Period', style: SelType.bodyMedium),
                    const SizedBox(height: SelSpace.x2),
                    Text(
                      period?.name ?? 'No active period',
                      style: SelType.bodyMuted,
                    ),
                  ],
                ),
              const SizedBox(height: SelSpace.x4),
              SelField(
                controller: _amount,
                label: 'Amount',
                hint: '500',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_conversionPreview(money, ref) != null) ...[
                const SizedBox(height: SelSpace.x2),
                Text(_conversionPreview(money, ref)!, style: SelType.small),
              ],
              const SizedBox(height: SelSpace.x4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Date given', style: SelType.bodyMedium),
                  const SizedBox(height: SelSpace.x2),
                  SelButton(
                    label: formatFirestoreDate(_dateGiven, pattern: 'd MMMM y'),
                    icon: LucideIcons.calendar,
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _dateGiven,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (d != null) setState(() => _dateGiven = d);
                    },
                  ),
                ],
              ),
              const SizedBox(height: SelSpace.x3),
              Align(
                alignment: Alignment.centerLeft,
                child: SelButton(
                  label: _showMore ? 'Less' : 'More',
                  kind: SelButtonKind.quiet,
                  dense: true,
                  trailingIcon: _showMore
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  onPressed: () => setState(() => _showMore = !_showMore),
                ),
              ),
              if (_showMore) ...[
                const SizedBox(height: SelSpace.x3),
                SelSelect<String>(
                  value: _sourceCurrency,
                  label: 'Currency',
                  onChanged: (v) => setState(() {
                    _sourceCurrency = v ?? SelectableCurrency.ghs;
                  }),
                  items: [
                    for (final code in SelectableCurrency.all)
                      DropdownMenuItem(
                        value: code,
                        child: Text(SelectableCurrency.label(code)),
                      ),
                  ],
                ),
                const SizedBox(height: SelSpace.x4),
                SelField(
                  controller: _notes,
                  label: 'Notes',
                  hint: 'Optional',
                  maxLines: 3,
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: SelSpace.x6),

        Row(
          children: [
            SelButton(
              label: 'Cancel',
              kind: SelButtonKind.quiet,
              onPressed: widget.embedded
                  ? () => Navigator.of(context).pop()
                  : () => context.go('/queue'),
            ),
            const Spacer(),
            SelButton.cyan(
              label: _isEdit ? 'Save changes' : 'Record gift',
              loading: _loading,
              onPressed: churchId == null || profile == null
                  ? null
                  : () => _submit(churchId, profile, entry),
            ),
          ],
        ),

        if (!_isEdit && idx?.isStaff == true) ...[
          const SizedBox(height: SelSpace.x4),
          Text(
            'Your entry goes to a pastor for review before it counts toward '
            'totals.',
            style: SelType.small,
          ),
        ],
        if (_partner != null && _amount.text.isNotEmpty) ...[
          const SizedBox(height: SelSpace.x4),
          Text(
            'Recording ${money(_resolveConversion(ref)?.amountBase ?? parseAmountInput(_amount.text) ?? 0)} '
            'for ${_partner!.fullName}.',
            style: SelType.small,
          ),
        ],
      ],
    );
  }

  CurrencyConversion? _resolveConversion(WidgetRef ref) {
    final sourceAmount = parseAmountInput(_amount.text);
    if (sourceAmount == null || sourceAmount <= 0) return null;
    final rates = ref.read(churchExchangeRatesProvider);
    return rates.convert(
      sourceAmount: sourceAmount,
      sourceCurrency: _sourceCurrency,
    );
  }

  String? _conversionPreview(String Function(num) money, WidgetRef ref) {
    final conversion = _resolveConversion(ref);
    if (conversion == null || conversion.isBaseCurrency) return null;
    return '≈ ${money(conversion.amountBase)} (rate ${conversion.exchangeRateToBase})';
  }

  Future<void> _pickPartner(
    BuildContext context,
    String churchId,
    String uid,
  ) async {
    if (!context.mounted) return;
    final chosen = await showPartnerPickerPanel(
      context,
      churchId: churchId,
      uid: uid,
    );
    if (chosen != null) setState(() => _partner = chosen);
  }

  Future<void> _submit(
    String churchId,
    ChurchUser staff,
    PartnershipEntry? entry,
  ) async {
    setState(() => _error = null);
    final conversion = _resolveConversion(ref);
    if (_partner == null) {
      setState(() => _error = 'Select a partner.');
      return;
    }
    if (_arm == null) {
      setState(() => _error = 'Select a partnership arm.');
      return;
    }
    final period = _period ?? ref.read(activePeriodProvider);
    if (period == null) {
      setState(() => _error = 'No active period.');
      return;
    }
    if (conversion == null) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    if (!conversion.rateAvailable) {
      // Without a rate the conversion is 1:1, which would bank a $100 gift as
      // ₵100. Better to stop here than to record a number nobody meant.
      setState(
        () => _error =
            'No exchange rate is set for ${conversion.sourceCurrency}. '
            'Add one in Settings before recording in this currency.',
      );
      return;
    }
    final amount = conversion.amountBase;

    setState(() => _loading = true);
    final repo = ref.read(entriesRepositoryProvider);
    final pSnap = {
      'memberId': _partner!.memberId,
      'fullName': _partner!.fullName,
      'fellowship': _partner!.fellowship,
      'email': _partner!.email,
      'phone': _partner!.phone,
    };
    final aSnap = {'name': _arm!.name};
    final perSnap = {
      'name': period.name,
      'startDate': Timestamp.fromDate(period.startDate),
      'endDate': Timestamp.fromDate(period.endDate),
    };

    try {
      if (_isEdit) {
        final existing =
            ref.read(entryDetailProvider(widget.entryId!)).valueOrNull ?? entry;
        if (existing == null) {
          setState(() => _error = 'Entry not found.');
          return;
        }
        final idx = ref.read(userChurchIndexProvider).valueOrNull;
        if (idx == null) {
          if (mounted) setState(() => _loading = false);
          return;
        }
        if (idx.isStaff) {
          await repo.staffUpdateEntry(
            churchId: churchId,
            existing: existing,
            staff: staff,
            partnerId: _partner!.id,
            partnerSnapshot: pSnap,
            partnershipArmId: _arm!.id,
            armSnapshot: aSnap,
            partnershipPeriodId: period.id,
            periodSnapshot: perSnap,
            amountCedis: amount,
            sourceCurrency: conversion.sourceCurrency,
            sourceAmount: conversion.sourceAmount,
            exchangeRateToBase: conversion.exchangeRateToBase,
            dateGiven: _dateGiven,
            notes: _notes.text,
          );
        } else if (idx.isPastor) {
          await repo.pastorUpdateEntry(
            churchId: churchId,
            existing: existing,
            pastor: staff,
            partnerId: _partner!.id,
            partnerSnapshot: pSnap,
            partnershipArmId: _arm!.id,
            armSnapshot: aSnap,
            partnershipPeriodId: period.id,
            periodSnapshot: perSnap,
            amountCedis: amount,
            sourceCurrency: conversion.sourceCurrency,
            sourceAmount: conversion.sourceAmount,
            exchangeRateToBase: conversion.exchangeRateToBase,
            dateGiven: _dateGiven,
            notes: _notes.text,
          );
        } else {
          setState(() => _error = 'Only staff or pastor can save changes.');
          return;
        }
        final statusAfter = idx.isStaff ? 'pending' : existing.status;
        final after = _afterEntryValues(
          partner: _partner!,
          arm: _arm!,
          period: period,
          amount: amount,
          dateGiven: _dateGiven,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          status: statusAfter,
        );
        await logPillrActivity(
          ref,
          churchId: churchId,
          action: 'entry.update',
          entityType: 'entry',
          entityId: existing.id,
          entitySnapshot: after,
          metadata: {'before': _entryValuesForActivityLog(existing)},
        );
        if (mounted) {
          if (widget.embedded) {
            selNotice(context, 'Entry updated.', kind: SelNoticeKind.success);
            Navigator.of(context).pop();
          } else {
            context.go('/entries/${widget.entryId}');
          }
        }
      } else {
        final idx = ref.read(userChurchIndexProvider).valueOrNull;
        if (idx != null && (idx.isPastor || idx.isStaff)) {
          final candidates = await repo.fetchEntriesForDuplicateCheck(
            churchId,
            partnerId: _partner!.id,
            allChurchEntries: idx.isPastor,
            createdByUid: idx.isStaff ? idx.uid : null,
          );
          if (hasSimilarPartnershipEntryWithSameDate(
            candidates,
            partnerId: _partner!.id,
            armId: _arm!.id,
            periodId: period.id,
            amount: amount,
            dateGiven: _dateGiven,
          )) {
            if (!mounted) return;
            final proceed = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text('Possible duplicate'),
                content: const Text(
                  'An entry already exists for this partner, arm, and period with a similar amount (within 10%). '
                  'Do you want to record another entry anyway?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Continue'),
                  ),
                ],
              ),
            );
            if (proceed != true) {
              if (mounted) setState(() => _loading = false);
              return;
            }
          }
        }
        final entryId = await repo.createEntry(
          churchId: churchId,
          staff: staff,
          partnerId: _partner!.id,
          partnerSnapshot: pSnap,
          partnershipArmId: _arm!.id,
          armSnapshot: aSnap,
          partnershipPeriodId: period.id,
          periodSnapshot: perSnap,
          amountCedis: amount,
          sourceCurrency: conversion.sourceCurrency,
          sourceAmount: conversion.sourceAmount,
          exchangeRateToBase: conversion.exchangeRateToBase,
          dateGiven: _dateGiven,
          notes: _notes.text,
        );
        final idxCreate = ref.read(userChurchIndexProvider).valueOrNull;
        await logPillrActivity(
          ref,
          churchId: churchId,
          action: 'entry.create',
          entityType: 'entry',
          entityId: entryId,
          entitySnapshot: _afterEntryValues(
            partner: _partner!,
            arm: _arm!,
            period: period,
            amount: amount,
            dateGiven: _dateGiven,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            status: idxCreate?.isPastor == true ? 'approved' : 'pending',
          ),
        );
        ref.invalidate(rankingEntriesProvider);
        invalidateEntryDerivedData(ref);
        if (mounted) {
          if (widget.embedded) {
            selNotice(
              context,
              idxCreate?.isPastor == true
                  ? 'Entry recorded and approved.'
                  : 'Entry submitted for review.',
              kind: SelNoticeKind.success,
            );
            Navigator.of(context).pop();
          } else {
            context.go('/entries/success/$entryId');
          }
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

/// Partner selection row.
///
/// When nothing is chosen this reads as an instruction rather than an empty
/// field — picking a partner is the first real decision on this screen, so it
/// gets a full-width target instead of a dropdown.
class _PartnerTile extends StatelessWidget {
  const _PartnerTile({required this.partner, required this.onTap});

  final Partner? partner;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = partner;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SelSpace.x3,
            vertical: SelSpace.x3,
          ),
          decoration: BoxDecoration(
            color: Sel.canvas,
            borderRadius: BorderRadius.circular(SelRadius.input),
            border: Border.all(color: Sel.borderMuted),
          ),
          child: Row(
            children: [
              Icon(
                p == null ? LucideIcons.search : LucideIcons.user,
                size: 15,
                color: Sel.warm,
              ),
              const SizedBox(width: SelSpace.x3),
              Expanded(
                child: p == null
                    ? Text(
                        'Search by name, member ID or fellowship',
                        style: SelType.bodyMuted,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(p.fullName, style: SelType.bodyMedium),
                          Text(
                            [
                              p.memberId,
                              p.fellowship,
                            ].where((e) => e.isNotEmpty).join(' · '),
                            style: SelType.small,
                          ),
                        ],
                      ),
              ),
              Text(
                p == null ? 'Choose' : 'Change',
                style: SelType.button.copyWith(color: Sel.cyanEdge),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
