import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/entry_duplicate_utils.dart';
import '../../design/seline.dart';
import '../../features/church/providers/church_settings_providers.dart';
import '../../features/activity/activity_log_helper.dart';
import '../../features/arms/domain/partnership_arm.dart';
import '../../features/arms/providers/arms_providers.dart';
import '../../features/auth/domain/church_user.dart';
import '../../features/auth/domain/user_church_index.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/partners/domain/partner.dart';
import '../../features/partners/presentation/partner_form_dialog.dart';
import '../../features/partners/providers/partners_providers.dart';
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
      maxWidth: 640,
      children: [
        SelPageTitle(
          title: _isEdit ? 'Edit entry' : 'Record a ',
          highlight: _isEdit ? null : 'partnership',
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
          subtitle: 'Who this partnership is from.',
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
              SelSelect<String>(
                value: _arm?.id,
                label: 'Partnership arm',
                hint: Text('Select an arm', style: SelType.bodyMuted),
                onChanged: (v) => setState(() {
                  _arm = arms.where((a) => a.id == v).firstOrNull;
                }),
                items: [
                  for (final a in arms)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
              ),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
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
              const SizedBox(height: SelSpace.x4),
              SelField(
                controller: _notes,
                label: 'Notes',
                hint: 'Optional',
                maxLines: 3,
              ),
            ],
          ),
        ),

        const SizedBox(height: SelSpace.x6),

        Row(
          children: [
            SelButton(
              label: 'Cancel',
              kind: SelButtonKind.quiet,
              onPressed: () => context.go('/queue'),
            ),
            const Spacer(),
            SelButton.cyan(
              label: _isEdit ? 'Save changes' : 'Record entry',
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
            'Recording ${money(double.tryParse(_amount.text.replaceAll(',', '')) ?? 0)} '
            'for ${_partner!.fullName}.',
            style: SelType.small,
          ),
        ],
      ],
    );
  }

  Future<void> _pickPartner(BuildContext context, String churchId, String uid) async {
    if (!context.mounted) return;
    final parentContext = context;
    final chosen = await showModalBottomSheet<Partner>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Sel.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SelRadius.card)),
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
                color: Sel.ash,
              ),
              const SizedBox(width: SelSpace.x3),
              Expanded(
                child: p == null
                    ? Text('Search by name, member ID or fellowship',
                        style: SelType.bodyMuted)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(p.fullName, style: SelType.bodyMedium),
                          Text(
                            [p.memberId, p.fellowship]
                                .where((e) => e.isNotEmpty)
                                .join(' · '),
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
        left: SelSpace.x6,
        right: SelSpace.x6,
        top: SelSpace.x2,
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
                  margin: const EdgeInsets.only(bottom: SelSpace.x4),
                  decoration: BoxDecoration(
                    color: Sel.border,
                    borderRadius: BorderRadius.circular(SelRadius.pill),
                  ),
                ),
              ),
              Text('Select partner', style: SelType.subtitle),
              const SizedBox(height: SelSpace.x4),
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Search by name, member ID, fellowship…',
                  filled: true,
                  fillColor: Sel.canvas,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SelRadius.input),
                    borderSide: const BorderSide(color: Sel.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SelRadius.input),
                    borderSide: const BorderSide(color: Sel.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SelRadius.input),
                    borderSide: const BorderSide(color: Sel.soot, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: SelSpace.x4, vertical: 14),
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(LucideIcons.search, color: Sel.ash, size: 20),
                  ),
                ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 280), () {
                  if (mounted) _load(v.trim());
                });
              },
            ),
            const SizedBox(height: SelSpace.x4),
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
