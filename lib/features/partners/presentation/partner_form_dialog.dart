import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/seline.dart';

import '../../../core/utils/text_case_utils.dart';
import '../../activity/activity_log_helper.dart';
import '../../church/providers/church_settings_providers.dart';
import '../domain/partner.dart';
import '../providers/partners_providers.dart';

class PartnerFormDialog extends ConsumerStatefulWidget {
  const PartnerFormDialog({
    super.key,
    required this.churchId,
    required this.uid,
    this.existing,
  });

  final String churchId;
  final String uid;
  final Partner? existing;

  @override
  ConsumerState<PartnerFormDialog> createState() => _PartnerFormDialogState();
}

class _PartnerFormDialogState extends ConsumerState<PartnerFormDialog> {
  late final TextEditingController _fullName;
  late final TextEditingController _fellowship;
  late final TextEditingController _email;
  late final TextEditingController _phone;
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
    _active = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _fellowship.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_fullName.text.trim().isEmpty || _fellowship.text.trim().isEmpty) {
      setState(() => _error = 'Full name and fellowship are required.');
      return;
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
          'fullName': ex.fullName,
          'fellowship': ex.fellowship,
          'email': ex.email,
          'phone': ex.phone,
          'isActive': ex.isActive,
        };
        await repo.updatePartner(
          churchId: widget.churchId,
          partner: ex,
          memberId: ex.memberId,
          fullName: _fullName.text,
          fellowship: _fellowship.text,
          email: _email.text,
          phone: _phone.text,
          isActive: _active,
        );
        final after = {
          'fullName': TextCaseUtils.toTitleCase(_fullName.text),
          'fellowship': TextCaseUtils.toTitleCase(_fellowship.text),
          'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
          'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return SelDialog(
      title: isEdit ? 'Edit partner' : 'Add partner',
      subtitle: isEdit
          ? 'Update member details for partnership records.'
          : 'Member ID is assigned automatically when you save.',
      width: 480,
      actions: [
        OutlinedButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isEdit) ...[
            Text('Member ID', style: SelType.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: SelSpace.x2),
            Text(
              widget.existing!.memberId,
              style: SelType.body.copyWith(fontWeight: FontWeight.w600),
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
          SelField(controller: _fellowship, label: 'Fellowship'),
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
            DecoratedBox(
              decoration: BoxDecoration(
                color: Sel.card,
                borderRadius: BorderRadius.circular(SelRadius.card),
                border: Border.all(color: Sel.border),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: SelSpace.x4, vertical: SelSpace.x2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Active', style: SelType.body.copyWith(fontWeight: FontWeight.w500)),
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
            const SizedBox(height: SelSpace.x2),
            Text(_error!, style: SelType.small.copyWith(color: Sel.ink)),
          ],
        ],
      ),
    );
  }
}
