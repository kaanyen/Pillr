import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_text_field.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../activity/activity_log_helper.dart';
import '../../auth/providers/auth_providers.dart';
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
        final churchName = ref.read(churchNameProvider).valueOrNull ?? 'Church';
        await repo.createPartner(
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
        );
      } else {
        await repo.updatePartner(
          churchId: widget.churchId,
          partner: widget.existing!,
          memberId: widget.existing!.memberId,
          fullName: _fullName.text,
          fellowship: _fellowship.text,
          email: _email.text,
          phone: _phone.text,
          isActive: _active,
        );
        await logPillrActivity(
          ref,
          churchId: widget.churchId,
          action: 'partner.update',
          entityType: 'partner',
          entityId: widget.existing!.id,
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
    return AlertDialog(
      title: Text(isEdit ? 'Edit partner' : 'Add partner', style: AppTypography.heading3),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isEdit) ...[
                Text('Member ID', style: AppTypography.label),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.existing!.memberId,
                  style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.sm),
              ] else ...[
                Text(
                  'Member ID is generated automatically: church initials + a random 6-digit number (e.g. FBC482193).',
                  style: AppTypography.caption.copyWith(color: AppColors.gray600),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              PillrTextField(controller: _fullName, label: 'Full name'),
              const SizedBox(height: AppSpacing.md),
              PillrTextField(controller: _fellowship, label: 'Fellowship'),
              const SizedBox(height: AppSpacing.md),
              PillrTextField(
                controller: _email,
                label: 'Email (optional)',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: AppSpacing.md),
              PillrTextField(
                controller: _phone,
                label: 'Phone (optional)',
                keyboardType: TextInputType.phone,
              ),
              if (isEdit) ...[
                const SizedBox(height: AppSpacing.md),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Active', style: AppTypography.body),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
              if (_error != null)
                Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.dangerColor)),
            ],
          ),
        ),
      ),
      actions: [
        PillrButton(
          label: 'Cancel',
          variant: PillrButtonVariant.ghost,
          onPressed: _loading ? null : () => Navigator.pop(context),
        ),
        PillrButton(
          label: isEdit ? 'Save' : 'Create',
          loading: _loading,
          onPressed: _loading ? null : _save,
          variant: PillrButtonVariant.primary,
        ),
      ],
    );
  }
}
