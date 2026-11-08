import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../../design/seline.dart';
import '../../auth/domain/church_user.dart';
import '../../auth/domain/user_church_index.dart';
import '../../users/providers/users_providers.dart';
import '../domain/church_settings.dart';
import '../domain/monthly_email_report.dart';
import '../providers/church_settings_providers.dart';
import '../../../core/errors/plain_error.dart';

/// Pastor/admin controls for the 15th-of-month partner giving letter.
class MonthlyPartnerEmailPanel extends ConsumerStatefulWidget {
  const MonthlyPartnerEmailPanel({
    super.key,
    required this.idx,
    required this.settings,
    this.bare = false,
  });

  final UserChurchIndex idx;
  final ChurchSettings settings;

  /// Without its own card, for Settings' two-column sections.
  final bool bare;

  @override
  ConsumerState<MonthlyPartnerEmailPanel> createState() =>
      _MonthlyPartnerEmailPanelState();
}

class _MonthlyPartnerEmailPanelState
    extends ConsumerState<MonthlyPartnerEmailPanel> {
  late bool _enabled;
  String? _pastorUid;
  late final TextEditingController _from;
  bool _seeded = false;
  bool _saving = false;
  bool _previewing = false;
  bool _running = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _enabled = widget.settings.sendMonthlyPartnerEmails;
    _pastorUid = widget.settings.primaryPastorUid;
    _from = TextEditingController(text: widget.settings.partnerEmailFrom ?? '');
    _seeded = true;
  }

  @override
  void didUpdateWidget(covariant MonthlyPartnerEmailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_seeded) {
      _enabled = widget.settings.sendMonthlyPartnerEmails;
      _pastorUid = widget.settings.primaryPastorUid;
      _from.text = widget.settings.partnerEmailFrom ?? '';
      _seeded = true;
    }
  }

  @override
  void dispose() {
    _from.dispose();
    super.dispose();
  }

  List<ChurchUser> _pastors(List<ChurchUser> users) {
    return users
        .where((u) => u.role == 'pastor' && u.isActive)
        .toList(growable: false);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final pastors =
          _pastors(ref.read(churchUsersProvider).valueOrNull ?? const []);
      final pastorUid =
          _pastorUid ?? (pastors.length == 1 ? pastors.first.uid : null);
      await ref.read(churchSettingsRepositoryProvider).updateMonthlyPartnerEmail(
            churchId: widget.settings.churchId,
            enabled: _enabled,
            primaryPastorUid: pastorUid,
            partnerEmailFrom: _from.text,
          );
      if (mounted) setState(() => _notice = 'Partner emails saved.');
    } catch (e) {
      if (mounted) setState(() => _notice = plainError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _preview() async {
    setState(() {
      _previewing = true;
      _notice = null;
    });
    try {
      final to =
          await ref.read(churchSettingsRepositoryProvider).previewMonthlyPartnerEmail();
      if (mounted) {
        setState(() => _notice = to.isEmpty
            ? 'Preview sent.'
            : 'Preview sent to $to.');
      }
    } catch (e) {
      if (mounted) setState(() => _notice = plainError(e));
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _run() async {
    final ok = await selConfirm(
      context,
      title: 'Email last month’s giving?',
      message:
          'Every partner who gave last month and has an email on file will get '
          'a letter from the pastor. People without an email are skipped and '
          'listed on the report. This cannot be undone for those already sent.',
      confirmLabel: 'Send letters',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _running = true;
      _notice = null;
    });
    try {
      final r =
          await ref.read(churchSettingsRepositoryProvider).runMonthlyPartnerEmails();
      if (!mounted) return;
      final dry = r.dryRun ? ' Dry run — nothing was emailed.' : '';
      setState(() {
        _notice =
            'Sent ${r.sent}, skipped ${r.skipped} (no email), failed ${r.failed}.$dry';
      });
    } catch (e) {
      if (mounted) setState(() => _notice = plainError(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(churchUsersProvider).valueOrNull ?? const <ChurchUser>[];
    final pastors = _pastors(users);
    final effectivePastorUid = _pastorUid ??
        (pastors.length == 1 ? pastors.first.uid : null);
    final pastorValue =
        pastors.any((p) => p.uid == effectivePastorUid) ? effectivePastorUid : null;
    final isPastor = widget.idx.isPastor;
    final report = isPastor
        ? ref.watch(latestMonthlyEmailReportProvider).valueOrNull
        : null;

    return SelPanel(
      bare: widget.bare,
      title: 'Monthly partner emails',
      subtitle:
          'On the 15th, partners who gave the month before get a letter from '
          'the pastor: that month by arm, then year to date. Off until you turn it on.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Send monthly letters', style: SelType.bodyMedium),
                    Text(
                      'Approved giving only. Partners with no email are skipped.',
                      style: SelType.small,
                    ),
                  ],
                ),
              ),
              Switch(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
            ],
          ),
          const SizedBox(height: SelSpace.x4),
          SelSelect<String>(
            label: 'Primary pastor',
            value: pastorValue,
            hint: const Text('Choose who the letter is from'),
            onChanged: (v) => setState(() => _pastorUid = v),
            items: [
              for (final p in pastors)
                DropdownMenuItem(
                  value: p.uid,
                  child: Text(p.fullName.isEmpty ? p.email : p.fullName),
                ),
            ],
          ),
          const SizedBox(height: SelSpace.x4),
          SelField(
            controller: _from,
            label: 'From address',
            hint: 'Partner Appreciation <pastor@theairportcitychurch.com>',
            helper:
                'Must be a mailbox on a domain verified in this church’s Resend account. Replies go to the primary pastor.',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: SelSpace.x6),
          Wrap(
            spacing: SelSpace.x2,
            runSpacing: SelSpace.x2,
            children: [
              widget.idx.isAdmin
                  ? SelButton(
                      label: 'Save',
                      loading: _saving,
                      onPressed: _saving ? null : _save,
                    )
                  : SelButton.cyan(
                      label: 'Save',
                      loading: _saving,
                      onPressed: _saving ? null : _save,
                    ),
              SelButton(
                label: 'Send preview to me',
                icon: LucideIcons.mail,
                loading: _previewing,
                onPressed: _previewing ? null : _preview,
              ),
              if (isPastor)
                SelButton(
                  label: 'Email last month now',
                  loading: _running,
                  onPressed: _running ? null : _run,
                ),
            ],
          ),
          if (_notice != null) ...[
            const SizedBox(height: SelSpace.x4),
            Text(_notice!, style: SelType.bodySm),
          ],
          if (report != null) ...[
            const SizedBox(height: SelSpace.x6),
            const Divider(height: 1, color: Sel.border),
            const SizedBox(height: SelSpace.x4),
            _ReportBlock(report: report),
          ],
        ],
      ),
    );
  }
}

class _ReportBlock extends StatelessWidget {
  const _ReportBlock({required this.report});

  final MonthlyEmailReport report;

  @override
  Widget build(BuildContext context) {
    final skipped = report.skippedNoEmail;
    final failed = report.failed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Last run — ${report.monthLabel}', style: SelType.bodyMedium),
        const SizedBox(height: SelSpace.x1),
        Text(
          [
            if (report.dryRun) 'Dry run',
            'Sent ${report.sent}',
            'Skipped ${skipped.length} (no email)',
            'Failed ${failed.length}',
            if (report.skipReason != null && report.skipReason!.isNotEmpty)
              report.skipReason!,
          ].join(' · '),
          style: SelType.small,
        ),
        if (skipped.isNotEmpty) ...[
          const SizedBox(height: SelSpace.x3),
          Text('No email on file', style: SelType.caption),
          const SizedBox(height: SelSpace.x1),
          for (final s in skipped.take(12))
            Text(
              s.memberId.isEmpty ? s.fullName : '${s.memberId} · ${s.fullName}',
              style: SelType.bodySm,
            ),
          if (skipped.length > 12)
            Text('and ${skipped.length - 12} more', style: SelType.small),
        ],
        if (failed.isNotEmpty) ...[
          const SizedBox(height: SelSpace.x3),
          Text('Failed', style: SelType.caption),
          const SizedBox(height: SelSpace.x1),
          for (final f in failed.take(8))
            Text('${f.fullName} — ${f.error}', style: SelType.bodySm),
        ],
      ],
    );
  }
}
