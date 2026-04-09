import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/pillr_date_picker.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_form_card.dart';
import '../../../common/widgets/pillr_form_dialog.dart';
import '../../../common/widgets/pillr_icon.dart';
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
              if (!_isEdit) ...[
                Text(title, style: AppTypography.heading2),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Choose who gave, then add amount and date — two quick steps.',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ] else
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
                title: _isEdit ? 'Entry' : 'Partnership entry',
                subtitle: _isEdit ? null : 'Partner first, then partnership details.',
                leading: _isEdit ? null : PillrFormDialog.leadingIcon(LucideIcons.filePlus),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FormSectionTitle(label: 'Partner'),
                    const SizedBox(height: AppSpacing.md),
                    _PartnerPickerTile(
                      partner: _partner,
                      onTap: () => _pickPartner(context, churchId, uid),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
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
                        icon: const PillrIcon(LucideIcons.userPlus, size: 18),
                        label: const Text('Create new partner'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Divider(height: 1, thickness: 1, color: AppColors.gray200),
                    const SizedBox(height: AppSpacing.lg),
                    const _FormSectionTitle(label: 'Partnership details'),
                    const SizedBox(height: AppSpacing.md),
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
                    OutlinedButton.icon(
                      onPressed: () async {
                        final d = await showPillrDatePicker(
                          context: context,
                          initialDate: _dateGiven,
                          firstDate: DateTime(DateTime.now().year - 2),
                          lastDate: DateTime(DateTime.now().year + 1),
                        );
                        if (d != null) setState(() => _dateGiven = d);
                      },
                      icon: const PillrIcon(LucideIcons.calendar, size: 18),
                      label: Text('Date given: ${_dateGiven.toIso8601String().split('T').first}'),
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
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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

class _FormSectionTitle extends StatelessWidget {
  const _FormSectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.body.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.gray900,
      ),
    );
  }
}

class _PartnerPickerTile extends StatelessWidget {
  const _PartnerPickerTile({
    required this.partner,
    required this.onTap,
  });

  final Partner? partner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final has = partner != null;
    return Material(
      color: AppColors.gray50,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(10),
                child: const PillrIcon(
                  LucideIcons.search,
                  size: 22,
                  color: AppColors.primaryColor,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      has ? 'Selected partner' : 'Select partner',
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      has ? partner!.fullName : 'Search by name, member ID, fellowship…',
                      style: AppTypography.body.copyWith(
                        fontWeight: has ? FontWeight.w600 : FontWeight.w400,
                        color: AppColors.gray900,
                      ),
                    ),
                  ],
                ),
              ),
              const PillrIcon(
                LucideIcons.chevronRight,
                color: AppColors.gray400,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
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
        top: AppSpacing.sm,
      ),
      child: SafeArea(
        child: SizedBox(
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.gray200,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text('Select partner', style: AppTypography.heading3),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Search by name, member ID, fellowship…',
                  filled: true,
                  fillColor: AppColors.gray50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: const BorderSide(color: AppColors.gray200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: const BorderSide(color: AppColors.gray200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: const BorderSide(color: AppColors.primaryColor, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(LucideIcons.search, color: AppColors.gray400, size: 20),
                  ),
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
                            leading: const Icon(LucideIcons.plus),
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
      ),
    );
  }
}
