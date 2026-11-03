import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../../core/navigation/panel_flows.dart';
import '../../../core/utils/text_case_utils.dart';
import '../../../design/seline.dart';
import '../../activity/activity_log_helper.dart';
import '../../auth/providers/auth_providers.dart';
import '../../church/providers/church_settings_providers.dart';
import '../domain/partner.dart';
import 'duplicate_warning.dart';
import '../providers/partners_providers.dart';

/// Add or edit a partner — body for [showPartnerFormPanel].
class PartnerFormPanel extends ConsumerStatefulWidget {
  const PartnerFormPanel({
    super.key,
    required this.churchId,
    required this.uid,
    this.existing,
  });

  final String churchId;
  final String uid;
  final Partner? existing;

  @override
  ConsumerState<PartnerFormPanel> createState() => _PartnerFormPanelState();
}

class _PartnerFormPanelState extends ConsumerState<PartnerFormPanel> {
  late final TextEditingController _fullName;
  late final TextEditingController _fellowship;
  late final TextEditingController _email;
  late final TextEditingController _phone;

  /// Numbers and emails beyond the main ones, one per line. A merge brings
  /// several together; they all keep finding this person.
  late final TextEditingController _otherPhones;
  late final TextEditingController _otherEmails;
  late final TextEditingController _memberId;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  bool _active = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _fullName = TextEditingController(text: e?.fullName ?? '');
    _fellowship = TextEditingController(text: e?.fellowship ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _otherPhones = TextEditingController(
      text: [
        for (final p in e?.allPhones ?? const <String>[])
          if (p != (e?.phone ?? '').trim()) p,
      ].join('\n'),
    );
    _otherEmails = TextEditingController(
      text: [
        for (final m in e?.allEmails ?? const <String>[])
          if (m != (e?.email ?? '').trim()) m,
      ].join('\n'),
    );
    _memberId = TextEditingController(text: e?.memberId ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _active = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _fellowship.dispose();
    _email.dispose();
    _phone.dispose();
    _otherPhones.dispose();
    _otherEmails.dispose();
    _memberId.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_fullName.text.trim().isEmpty || _fellowship.text.trim().isEmpty) {
      setState(() => _error = 'Full name and fellowship are required.');
      return;
    }
    final ex = widget.existing;
    if (ex != null) {
      final problem = await _memberIdProblem(ex);
      if (problem != null) {
        if (mounted) setState(() => _error = problem);
        return;
      }
      if (!mounted) return;
    }
    // A new person, or a name changed into someone who may already be here.
    final renamed =
        ex != null &&
        _fullName.text.trim().toLowerCase() != ex.fullName.trim().toLowerCase();
    if (ex == null || renamed) {
      setState(() => _loading = true);
      bool goAhead;
      try {
        goAhead = await confirmNotDuplicate(
          context,
          ref,
          churchId: widget.churchId,
          fullName: _fullName.text,
          phone: _phone.text,
          email: _email.text,
          fellowship: _fellowship.text,
          editingPartnerId: ex?.id,
        );
      } catch (_) {
        // The check is advice. If it cannot load, the save says what is wrong.
        goAhead = true;
      }
      if (!goAhead) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      if (!mounted) return;
    }
    setState(() => _loading = true);
    final repo = ref.read(partnersRepositoryProvider);
    try {
      if (widget.existing == null) {
        final churchName = ref.read(churchNameProvider) ?? 'Church';
        final created = await repo.createPartner(
          churchId: widget.churchId,
          uid: widget.uid,
          fullName: _fullName.text,
          fellowship: _fellowship.text,
          email: _email.text,
          phone: _phone.text,
          churchDisplayName: churchName,
        );
        await logPillrActivity(
          ref,
          churchId: widget.churchId,
          action: 'partner.create',
          entityType: 'partner',
          entityId: created.id,
          entitySnapshot: {
            'memberId': created.memberId,
            'fullName': TextCaseUtils.toTitleCase(_fullName.text),
            'fellowship': TextCaseUtils.toTitleCase(_fellowship.text),
          },
        );
      } else {
        final ex = widget.existing!;
        final before = {
          'memberId': ex.memberId,
          'fullName': ex.fullName,
          'fellowship': ex.fellowship,
          'email': ex.email,
          'phone': ex.phone,
          'phones': ex.allPhones,
          'emails': ex.allEmails,
          'address': ex.address,
          'notes': ex.notes,
          'isActive': ex.isActive,
        };
        await repo.updatePartner(
          churchId: widget.churchId,
          partner: ex,
          memberId: _memberId.text,
          fullName: _fullName.text,
          fellowship: _fellowship.text,
          email: _email.text,
          phone: _phone.text,
          isActive: _active,
          phones: _lines(_phone.text, _otherPhones.text),
          emails: _lines(_email.text, _otherEmails.text),
          address: _address.text,
          notes: _notes.text,
        );
        final after = {
          'memberId': _memberId.text.trim().toUpperCase(),
          'fullName': TextCaseUtils.toTitleCase(_fullName.text),
          'fellowship': TextCaseUtils.toTitleCase(_fellowship.text),
          'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
          'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          'phones': _lines(_phone.text, _otherPhones.text),
          'emails': _lines(_email.text, _otherEmails.text),
          'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          'isActive': _active,
        };
        await logPillrActivity(
          ref,
          churchId: widget.churchId,
          action: 'partner.update',
          entityType: 'partner',
          entityId: ex.id,
          metadata: {'before': before, 'after': after},
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Why the member ID can't be saved, or null. A changed ID must be free:
  /// not anyone's current ID, and not one anyone had before.
  Future<String?> _memberIdProblem(Partner ex) async {
    final id = _memberId.text.trim().toUpperCase();
    if (id == ex.memberId.trim().toUpperCase()) return null;
    if (id.isEmpty) return 'Member ID is required.';
    if (!RegExp(r'^[A-Z0-9-]+$').hasMatch(id)) {
      return 'Member ID can only have letters, numbers and dashes.';
    }
    if (ex.formerMemberIds.contains(id)) {
      return '$id is one of this person\'s old IDs. Pick a new one.';
    }
    setState(() => _loading = true);
    try {
      final taken = await ref
          .read(partnersRepositoryProvider)
          .memberIdExists(widget.churchId, id, excludePartnerId: ex.id);
      return taken ? '$id already belongs to someone, now or before.' : null;
    } catch (e) {
      return '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    // Staff edit names, IDs and contacts. Moving fellowship and closing a
    // partner stay with the pastor, or go through the recorded move.
    final staff =
        isEdit &&
        ref.watch(userChurchIndexProvider).valueOrNull?.role == 'staff';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isEdit) ...[
          SelField(
            controller: _memberId,
            label: 'Member ID',
            textCapitalization: TextCapitalization.characters,
            helper:
                'If you change it, the old ID stays with this person, so '
                'old receipts and sheets still find them.',
          ),
          const SizedBox(height: SelSpace.x4),
        ] else ...[
          Text(
            'Church initials + a random 6-digit number (e.g. FBC482193).',
            style: SelType.small.copyWith(color: Sel.warm, height: 1.4),
          ),
          const SizedBox(height: SelSpace.x4),
        ],
        SelField(controller: _fullName, label: 'Full name'),
        const SizedBox(height: SelSpace.x4),
        SelField(
          controller: _fellowship,
          label: 'Fellowship',
          enabled: !staff,
          helper: staff
              ? 'To move them, use Move partners on the Fellowships page, '
                    'so it can be undone.'
              : null,
        ),
        const SizedBox(height: SelSpace.x4),
        SelField(
          controller: _email,
          label: 'Email (optional)',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: SelSpace.x4),
        SelField(
          controller: _phone,
          label: 'Phone (optional)',
          keyboardType: TextInputType.phone,
        ),
        if (isEdit) ...[
          const SizedBox(height: SelSpace.x4),
          SelField(
            controller: _otherPhones,
            label: 'Other phone numbers (one per line)',
            keyboardType: TextInputType.multiline,
            maxLines: 3,
          ),
          const SizedBox(height: SelSpace.x4),
          SelField(
            controller: _otherEmails,
            label: 'Other emails (one per line)',
            keyboardType: TextInputType.multiline,
            maxLines: 3,
          ),
          const SizedBox(height: SelSpace.x4),
          SelField(
            controller: _address,
            label: 'Address (optional)',
            keyboardType: TextInputType.multiline,
            maxLines: 2,
          ),
          const SizedBox(height: SelSpace.x4),
          SelField(
            controller: _notes,
            label: 'Notes (optional)',
            keyboardType: TextInputType.multiline,
            maxLines: 3,
          ),
        ],
        if (isEdit && !staff) ...[
          const SizedBox(height: SelSpace.x4),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Sel.canvas,
              borderRadius: BorderRadius.circular(SelRadius.card),
              border: Border.all(color: Sel.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SelSpace.x4,
                vertical: SelSpace.x2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Active',
                      style: SelType.body.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Switch.adaptive(
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: SelSpace.x3),
          Text(_error!, style: SelType.small.copyWith(color: Sel.ink)),
        ],
        const SizedBox(height: SelSpace.x6),
        Row(
          children: [
            SelButton(
              label: 'Cancel',
              kind: SelButtonKind.quiet,
              onPressed: _loading ? null : () => Navigator.pop(context),
            ),
            const Spacer(),
            SelButton.cyan(
              label: isEdit ? 'Save' : 'Create',
              loading: _loading,
              onPressed: _loading ? null : _save,
            ),
          ],
        ),
      ],
    );
  }
}

/// The main value first, then each other line, blanks dropped.
List<String> _lines(String main, String others) => [
  if (main.trim().isNotEmpty) main.trim(),
  for (final l in others.split(RegExp(r'[\n,;]+')))
    if (l.trim().isNotEmpty && l.trim() != main.trim()) l.trim(),
];
