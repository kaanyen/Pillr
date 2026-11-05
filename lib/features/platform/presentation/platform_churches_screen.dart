import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/notifications/sel_notice.dart';
import '../../../design/seline.dart';

import '../../../core/errors/error_handler.dart';
import '../data/platform_repository.dart';
import '../providers/platform_providers.dart';

class PlatformChurchesScreen extends ConsumerStatefulWidget {
  const PlatformChurchesScreen({super.key});

  @override
  ConsumerState<PlatformChurchesScreen> createState() =>
      _PlatformChurchesScreenState();
}

class _PlatformChurchesScreenState
    extends ConsumerState<PlatformChurchesScreen> {
  final _bootstrapEmail = TextEditingController();
  String _bootstrapRole = 'pastor';
  String? _formError;
  bool _inviting = false;

  @override
  void dispose() {
    _bootstrapEmail.dispose();
    super.dispose();
  }

  Future<void> _sendBootstrapInvite() async {
    setState(() {
      _formError = null;
      _inviting = true;
    });
    try {
      await ref
          .read(platformRepositoryProvider)
          .createBootstrapInvite(
            email: _bootstrapEmail.text,
            role: _bootstrapRole,
          );
      if (mounted) {
        _bootstrapEmail.clear();
        selNotice(
          context,
          'Bootstrap invite sent.',
          kind: SelNoticeKind.success,
        );
      }
    } catch (e) {
      setState(() => _formError = humanizeAuthException(e));
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  Future<void> _toggleActive(PlatformChurchSummary row) async {
    try {
      await ref
          .read(platformRepositoryProvider)
          .setChurchActive(churchId: row.churchId, isActive: !row.isActive);
      ref.invalidate(platformChurchesListProvider);
    } catch (e) {
      if (mounted) {
        selNotice(context, humanizeAuthException(e), kind: SelNoticeKind.error);
      }
    }
  }

  void _showDetail(PlatformChurchSummary row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.92,
          builder: (_, scroll) {
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.all(SelSpace.x6),
              children: [
                Text(row.name, style: SelType.title),
                const SizedBox(height: SelSpace.x2),
                SelectableText('ID: ${row.churchId}', style: SelType.small),
                const SizedBox(height: SelSpace.x4),
                if (row.logoUrl != null && row.logoUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(SelRadius.pill),
                    child: CachedNetworkImage(
                      imageUrl: row.logoUrl!,
                      height: 80,
                      fit: BoxFit.contain,
                    ),
                  ),
                const SizedBox(height: SelSpace.x4),
                Text(
                  'Contact',
                  style: SelType.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [row.primaryContactName, row.contactEmail, row.contactPhone]
                      .where((e) => e != null && e.toString().trim().isNotEmpty)
                      .join('\n'),
                  style: SelType.body,
                ),
                const SizedBox(height: SelSpace.x4),
                Text(
                  'Location',
                  style: SelType.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [row.address, row.city, row.region, row.country]
                      .where((e) => e != null && e.toString().trim().isNotEmpty)
                      .join(', '),
                  style: SelType.body,
                ),
                const SizedBox(height: SelSpace.x4),
                Text('Active users: ${row.activeUsers}', style: SelType.body),
                Text('Currency: ${row.currency ?? '—'}', style: SelType.body),
                Text(
                  'Setup completed: ${row.churchSetupCompletedAt != null ? 'yes' : 'no'}',
                  style: SelType.body,
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _filter = 'all';
  String _query = '';

  static String _status(PlatformChurchSummary r) => !r.isActive
      ? 'paused'
      : r.churchSetupCompletedAt == null
      ? 'waiting'
      : 'active';

  Future<void> _openAddChurch() async {
    _formError = null;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Sel.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SelRadius.card),
          ),
          title: Text('Add a church', style: SelType.subtitle),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Pillr emails the first admin a setup code. They name the '
                  'church and open its first giving period.',
                  style: SelType.bodySm,
                ),
                const SizedBox(height: SelSpace.x4),
                SelField(
                  controller: _bootstrapEmail,
                  label: "First admin's email",
                  hint: 'pastor@church.org',
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: LucideIcons.mail,
                ),
                const SizedBox(height: SelSpace.x4),
                SelSelect<String>(
                  value: _bootstrapRole,
                  label: 'Their role',
                  items: const [
                    DropdownMenuItem(value: 'pastor', child: Text('Pastor')),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Church admin'),
                    ),
                  ],
                  onChanged: (v) =>
                      setLocal(() => _bootstrapRole = v ?? 'pastor'),
                ),
                if (_formError != null) ...[
                  const SizedBox(height: SelSpace.x3),
                  Text(
                    _formError!,
                    style: SelType.bodySm.copyWith(color: Sel.danger),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            SelButton(
              label: 'Cancel',
              kind: SelButtonKind.quiet,
              onPressed: () => Navigator.pop(ctx),
            ),
            SelButton.cyan(
              label: 'Send setup code',
              icon: LucideIcons.send,
              loading: _inviting,
              onPressed: () async {
                setLocal(() {});
                await _sendBootstrapInvite();
                if (!ctx.mounted) return;
                if (_formError == null) {
                  Navigator.pop(ctx);
                } else {
                  setLocal(() {});
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(platformChurchesListProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: Sel.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Sel.ink,
            padding: EdgeInsets.symmetric(
              horizontal: wide ? SelSpace.x10 : SelSpace.x4,
              vertical: SelSpace.x4,
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  const PillrMark(size: 36, onNavy: true),
                  const SizedBox(width: SelSpace.x3),
                  Text(
                    'pillr',
                    style: SelType.hero.copyWith(
                      fontSize: 26,
                      height: 1,
                      letterSpacing: -1.2,
                      color: Sel.card,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Sel.card.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(SelRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.shieldCheck,
                          size: 14,
                          color: Sel.card,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Platform admin',
                          style: SelType.tag.copyWith(color: Sel.card),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: SelSpace.x4),
                  TextButton.icon(
                    onPressed: () => context.go('/overview'),
                    icon: const Icon(
                      LucideIcons.arrowLeft,
                      size: 16,
                      color: Sel.card,
                    ),
                    label: Text(
                      'My church',
                      style: SelType.bodySm.copyWith(
                        color: Sel.card,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: list.when(
              loading: () => const Center(child: PillrLoader(size: 48)),
              error: (e, _) => Center(child: SelError(message: '$e')),
              data: (rows) {
                int count(String f) => f == 'all'
                    ? rows.length
                    : rows.where((r) => _status(r) == f).length;
                final shown = rows.where((r) {
                  if (_filter != 'all' && _status(r) != _filter) return false;
                  if (_query.isEmpty) return true;
                  return r.name.toLowerCase().contains(_query) ||
                      (r.primaryContactName ?? '').toLowerCase().contains(
                        _query,
                      ) ||
                      (r.contactEmail ?? '').toLowerCase().contains(_query);
                }).toList();
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(platformChurchesListProvider),
                  child: SelPageBody(
                    children: [
                      SelPageTitle(
                        title: 'Churches on Pillr',
                        subtitle:
                            'You manage churches here. Their giving stays private to them.',
                        actions: [
                          SelButton.cyan(
                            label: 'Add a church',
                            icon: LucideIcons.plus,
                            onPressed: _openAddChurch,
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: SelSpace.x3,
                        runSpacing: SelSpace.x3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SelPillGroup<String>(
                            selected: _filter,
                            onChanged: (v) => setState(() => _filter = v),
                            options: [
                              ('all', 'All · ${count('all')}'),
                              ('active', 'Active · ${count('active')}'),
                              (
                                'waiting',
                                'Waiting for setup · ${count('waiting')}',
                              ),
                              ('paused', 'Paused · ${count('paused')}'),
                            ],
                          ),
                          SizedBox(
                            width: 320,
                            child: SelField(
                              hint: 'Find a church or admin',
                              prefixIcon: LucideIcons.search,
                              onChanged: (v) => setState(
                                () => _query = v.trim().toLowerCase(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: SelSpace.x4),
                      SelLedger(
                        minWidth: 820,
                        columns: const [
                          SelColumn('Church', flex: 3),
                          SelColumn('First admin', flex: 3),
                          SelColumn.numeric('People', width: 90),
                          SelColumn('Status', flex: 2),
                          SelColumn.numeric('', width: 200),
                        ],
                        emptyState: const SelEmpty(
                          title: 'No churches here',
                          message: 'Try another filter, or add a church.',
                          icon: LucideIcons.church,
                        ),
                        rows: [
                          for (final r in shown)
                            SelRow(
                              onTap: () => _showDetail(r),
                              cells: [
                                _ChurchCell(row: r),
                                SelCell.stacked(
                                  r.primaryContactName ?? '—',
                                  r.contactEmail ?? '',
                                ),
                                SelCell.numeric(
                                  '${r.activeUsers}',
                                  strong: false,
                                ),
                                _StatusDot(status: _status(r)),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    SelIconButton(
                                      icon: LucideIcons.copy,
                                      tooltip: 'Copy church ID',
                                      onPressed: () {
                                        Clipboard.setData(
                                          ClipboardData(text: r.churchId),
                                        );
                                        selNotice(
                                          context,
                                          'Church ID copied',
                                          kind: SelNoticeKind.success,
                                        );
                                      },
                                    ),
                                    const SizedBox(width: SelSpace.x2),
                                    SelButton(
                                      label: r.isActive ? 'Pause' : 'Resume',
                                      icon: r.isActive
                                          ? LucideIcons.pause
                                          : LucideIcons.play,
                                      dense: true,
                                      onPressed: () => _toggleActive(r),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: SelSpace.x4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            LucideIcons.helpCircle,
                            size: 18,
                            color: Sel.warm,
                          ),
                          const SizedBox(width: SelSpace.x3),
                          Expanded(
                            child: Text(
                              "Pausing locks a church's people out but keeps every "
                              'record. They see who to contact. Nothing is deleted, '
                              'and Resume puts everything back.',
                              style: SelType.bodySm.copyWith(color: Sel.text),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChurchCell extends StatelessWidget {
  const _ChurchCell({required this.row});

  final PlatformChurchSummary row;

  @override
  Widget build(BuildContext context) {
    final words = row.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    final initials = words.take(2).map((w) => w[0].toUpperCase()).join();
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: row.isActive ? Sel.skyWash : Sel.track,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            initials.isEmpty ? '?' : initials,
            style: SelType.bodyMedium.copyWith(
              fontWeight: FontWeight.w800,
              color: row.isActive ? Sel.ink : Sel.warm,
            ),
          ),
        ),
        const SizedBox(width: SelSpace.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                row.name,
                style: SelType.bodyMedium.copyWith(fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                row.churchId,
                style: SelType.small.copyWith(fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'paused' => (Sel.ash, 'Paused'),
      'waiting' => (Sel.sky, 'Waiting for setup'),
      _ => (const Color(0xFF22A06B), 'Active'),
    };
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: SelSpace.x2),
        Flexible(
          child: Text(
            label,
            style: SelType.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
