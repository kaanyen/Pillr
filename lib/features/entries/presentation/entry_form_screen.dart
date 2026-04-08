import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_form_card.dart';
import '../../../common/widgets/pillr_text_field.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/utils/entry_duplicate_utils.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/pillr_layout.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../activity/activity_log_helper.dart';
import '../../arms/domain/partnership_arm.dart';
import '../../arms/providers/arms_providers.dart';
import '../../auth/domain/church_user.dart';
import '../../auth/domain/user_church_index.dart';
import '../../auth/providers/auth_providers.dart';
import '../../partners/domain/partner.dart';
import '../../partners/presentation/partner_form_dialog.dart';
import '../../partners/providers/partners_providers.dart';
import '../../periods/domain/partnership_period.dart';
import '../../periods/providers/periods_providers.dart';
import '../domain/partnership_entry.dart';
import '../providers/entries_providers.dart';

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
}) =>
    {
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
  const EntryFormScreen({super.key, this.entryId});

  /// When non-null, loads [entryId] and saves via staff/pastor update.
  final String? entryId;

  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends ConsumerState<EntryFormScreen> {
  Partner? _partner;
  PartnershipArm? _arm;
  PartnershipPeriod? _period;
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  DateTime _dateGiven = DateTime.now();
  bool _loading = false;
  String? _error;
  bool _seeded = false;

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
    _amount.text = _formatAmount(entry.amountCedis);
    _notes.text = entry.notes ?? '';
    _dateGiven = entry.dateGiven;
  }

  String _formatAmount(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toString();
  }

  List<PartnershipArm> _armsForForm(PartnershipEntry? entry, List<PartnershipArm> all) {
    if (!_isEdit || entry == null) {
      return all.where((a) => a.isActive).toList();
    }
    return all.where((a) => a.isActive || a.id == entry.partnershipArmId).toList();
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
                onPressed: () => context.go('/entries'),
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
    PartnershipEntry? entry,
    PartnershipPeriod? activePeriodFallback,
  }) {
    if (idx == null || profile == null || churchId == null || uid == null) {
      return const Center(child: Text('Sign in required'));
    }

    final activeArms = _armsForForm(entry, armList);
    final title = _isEdit ? 'Edit entry' : 'New entry';
    final periodForCreate = activePeriodFallback ?? _period;
    if (!_isEdit && periodForCreate == null) {
      // Create mode: warn if no active period
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: PillrLayout.formMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: AppTypography.heading2),
              const SizedBox(height: AppSpacing.md),
              if (!_isEdit && periodForCreate == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(
                    'No active partnership period. A pastor must activate a period under Periods.',
                    style: AppTypography.caption.copyWith(color: AppColors.warningColor),
                  ),
                ),
              if (_isEdit && entry != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(
                    'Status: ${entry.status}',
                    style: AppTypography.caption.copyWith(color: AppColors.gray600),
                  ),
                ),
              PillrFormCard(
                title: 'Partner',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickPartner(context, churchId, uid),
                      icon: const Icon(Icons.person_search_outlined),
                      label: Text(_partner?.displayLabel ?? 'Select partner'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: () async {
                        await showDialog<void>(
                          context: context,
                          builder: (ctx) => PartnerFormDialog(
                            churchId: churchId,
                            uid: uid,
                            existing: null,
                          ),
                        );
                      },
                      child: const Text('Create new partner'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PillrFormCard(
                title: 'Entry details',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Partnership arm', style: AppTypography.label),
                    const SizedBox(height: AppSpacing.sm),
                    DropdownMenu<String>(
                      key: ValueKey<String?>('arm-${_arm?.id}'),
                      initialSelection: _arm?.id,
                      label: const Text('Select arm'),
                      dropdownMenuEntries: [
                        for (final a in activeArms) DropdownMenuEntry<String>(value: a.id, label: a.name),
                      ],
                      onSelected: (id) {
                        if (id == null) return;
                        PartnershipArm? found;
                        for (final a in activeArms) {
                          if (a.id == id) found = a;
                        }
                        setState(() => _arm = found);
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Period', style: AppTypography.label),
                    const SizedBox(height: AppSpacing.sm),
                    if (_isEdit)
                      DropdownMenu<String>(
                        key: ValueKey<String?>('period-${_period?.id}'),
                        initialSelection: _period?.id,
                        label: const Text('Partnership period'),
                        dropdownMenuEntries: [
                          for (final p in periodList)
                            DropdownMenuEntry<String>(value: p.id, label: p.name),
                        ],
                        onSelected: (id) {
                          if (id == null) return;
                          PartnershipPeriod? found;
                          for (final p in periodList) {
                            if (p.id == id) found = p;
                          }
                          setState(() => _period = found);
                        },
                      )
                    else
                      Text(
                        periodForCreate?.name ?? '—',
                        style: AppTypography.body,
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    PillrTextField(
                      controller: _amount,
                      label: 'Amount (₵)',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _dateGiven,
                          firstDate: DateTime(DateTime.now().year - 2),
                          lastDate: DateTime(DateTime.now().year + 1),
                        );
                        if (d != null) setState(() => _dateGiven = d);
                      },
                      child: Text('Date given: ${_dateGiven.toIso8601String().split('T').first}'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PillrTextField(controller: _notes, label: 'Notes (optional)', maxLines: 2),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.dangerColor)),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    PillrButton(
                      label: _isEdit ? 'Save changes' : 'Submit entry',
                      loading: _loading,
                      onPressed: _loading ? null : () => _submit(churchId, profile, entry),
                      variant: PillrButtonVariant.primary,
                      expanded: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPartner(BuildContext context, String churchId, String uid) async {
    if (!context.mounted) return;
    final parentContext = context;
    final chosen = await showModalBottomSheet<Partner>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PartnerPickerSheet(
        churchId: churchId,
        uid: uid,
        parentContext: parentContext,
      ),
    );
    if (chosen != null) setState(() => _partner = chosen);
  }

  Future<void> _submit(String churchId, ChurchUser staff, PartnershipEntry? entry) async {
    setState(() => _error = null);
    final amount = double.tryParse(_amount.text.replaceAll(',', ''));
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
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }

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
        final existing = ref.read(entryDetailProvider(widget.entryId!)).valueOrNull ?? entry;
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
        if (mounted) context.go('/entries/${widget.entryId}');
      } else {
        final idx = ref.read(userChurchIndexProvider).valueOrNull;
        if (idx != null && (idx.isPastor || idx.isStaff)) {
          final candidates = await repo.fetchEntriesForDuplicateCheck(
            churchId,
            partnerId: _partner!.id,
            allChurchEntries: idx.isPastor,
            createdByUid: idx.isStaff ? idx.uid : null,
          );
          if (hasSimilarPartnershipEntry(
            candidates,
            partnerId: _partner!.id,
            armId: _arm!.id,
            periodId: period.id,
            amount: amount,
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
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
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
          dateGiven: _dateGiven,
          notes: _notes.text,
        );
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
            status: 'pending',
          ),
        );
        ref.invalidate(entriesListProvider);
        if (mounted) context.go('/entries/success/$entryId');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _PartnerPickerSheet extends ConsumerStatefulWidget {
  const _PartnerPickerSheet({
    required this.churchId,
    required this.uid,
    required this.parentContext,
  });

  final String churchId;
  final String uid;
  final BuildContext parentContext;

  @override
  ConsumerState<_PartnerPickerSheet> createState() => _PartnerPickerSheetState();
}

class _PartnerPickerSheetState extends ConsumerState<_PartnerPickerSheet> {
  late final TextEditingController _controller;
  Timer? _debounce;
  List<Partner> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _load('');
  }

  Future<void> _load(String q) async {
    if (!mounted) return;
    setState(() => _loading = true);
    final repo = ref.read(partnersRepositoryProvider);
    final list = await repo.searchPartners(widget.churchId, q);
    if (!mounted) return;
    setState(() {
      _results = list;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
      ),
      child: SizedBox(
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Select partner', style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Search by name, member ID, fellowship…',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 280), () {
                  if (mounted) _load(v.trim());
                });
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _results.length + 1,
                      itemBuilder: (context, i) {
                        if (i == _results.length) {
                          return ListTile(
                            leading: const Icon(Icons.add),
                            title: const Text('Create new partner'),
                            onTap: () {
                              Navigator.pop(context);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!widget.parentContext.mounted) return;
                                showDialog<void>(
                                  context: widget.parentContext,
                                  builder: (dctx) => PartnerFormDialog(
                                    churchId: widget.churchId,
                                    uid: widget.uid,
                                    existing: null,
                                  ),
                                );
                              });
                            },
                          );
                        }
                        final p = _results[i];
                        return ListTile(
                          title: Text(p.fullName),
                          subtitle: Text(p.displayLabel),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
