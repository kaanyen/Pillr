import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../common/widgets/pillr_button.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/pdf_report_utils.dart';
import '../../activity/domain/activity_log_row.dart';
import '../../activity/providers/activity_log_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../church/providers/church_settings_providers.dart';

class ActivityLogsScreen extends ConsumerStatefulWidget {
  const ActivityLogsScreen({super.key});

  @override
  ConsumerState<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends ConsumerState<ActivityLogsScreen> {
  final _search = TextEditingController();
  String? _actionFilter;
  String? _entityFilter;
  DateTime? _from;
  DateTime? _to;
  int _pageSize = 20;
  static final _fmt = DateFormat('MMM d, y · HH:mm');

  final List<ActivityLogRow> _loaded = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _loadError;
  bool _scheduledInitial = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _ensureInitialLoad() {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null || !idx.isAdmin || _scheduledInitial) return;
    _scheduledInitial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFirst();
    });
  }

  Future<void> _loadFirst() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null || !idx.isAdmin) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await ref.read(activityLogRepositoryProvider).fetchActivityLogsPage(
            idx.churchId,
            pageSize: 50,
          );
      if (!mounted) return;
      setState(() {
        _loaded
          ..clear()
          ..addAll(page.items);
        _cursor = page.lastDoc;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null || !idx.isAdmin) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(activityLogRepositoryProvider).fetchActivityLogsPage(
            idx.churchId,
            pageSize: 50,
            startAfter: _cursor,
          );
      if (!mounted) return;
      setState(() {
        _loaded.addAll(page.items);
        _cursor = page.lastDoc;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    if (idx == null || !idx.isAdmin) {
      return const Center(child: Text('Activity logs are limited to admins.'));
    }

    ref.listen(userChurchIndexProvider, (prev, next) {
      final pc = prev?.valueOrNull?.churchId;
      final nc = next.valueOrNull?.churchId;
      if (pc != nc) {
        _loaded.clear();
        _cursor = null;
        _hasMore = true;
        _scheduledInitial = false;
        _ensureInitialLoad();
      }
    });

    _ensureInitialLoad();

    final all = _loaded;
    final actions = <String>{};
    final entities = <String>{};
    for (final l in all) {
      if (l.action.isNotEmpty) actions.add(l.action);
      if (l.entityType.isNotEmpty) entities.add(l.entityType);
    }
    final sortedActions = actions.toList()..sort();
    final sortedEntities = entities.toList()..sort();

    var filtered = all.where((l) {
      final q = _search.text.trim().toLowerCase();
      if (q.isNotEmpty) {
        final hit = l.actorName.toLowerCase().contains(q) ||
            (l.entityId ?? '').toLowerCase().contains(q);
        if (!hit) return false;
      }
      if (_actionFilter != null && _actionFilter!.isNotEmpty && l.action != _actionFilter) {
        return false;
      }
      if (_entityFilter != null && _entityFilter!.isNotEmpty && l.entityType != _entityFilter) {
        return false;
      }
      if (_from != null) {
        final start = DateTime(_from!.year, _from!.month, _from!.day);
        if (l.createdAt.isBefore(start)) return false;
      }
      if (_to != null) {
        final end = DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59);
        if (l.createdAt.isAfter(end)) return false;
      }
      return true;
    }).toList();

    final page = filtered.take(_pageSize).toList();

    if (_loadError != null && !_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$_loadError', style: AppTypography.body),
            const SizedBox(height: AppSpacing.md),
            PillrButton(
              label: 'Retry',
              onPressed: _loadFirst,
              variant: PillrButtonVariant.primary,
            ),
          ],
        ),
      );
    }

    if (_loading && _loaded.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Activity logs', style: AppTypography.heading2)),
              PillrButton(
                label: 'Export PDF',
                variant: PillrButtonVariant.secondary,
                onPressed: filtered.isEmpty ? null : () => _exportPdf(filtered),
              ),
              const SizedBox(width: AppSpacing.sm),
              PillrButton(
                label: 'Export CSV',
                variant: PillrButtonVariant.secondary,
                onPressed: filtered.isEmpty ? null : () => _exportCsv(filtered),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Newest first. Filters apply to events loaded from the server; use Load more for older rows.',
            style: AppTypography.caption,
          ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'Search actor name or entity ID…',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey('action-$_actionFilter'),
                      initialValue: _actionFilter,
                      decoration: const InputDecoration(
                        labelText: 'Action',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All actions')),
                        for (final a in sortedActions)
                          DropdownMenuItem<String?>(value: a, child: Text(a)),
                      ],
                      onChanged: (v) => setState(() => _actionFilter = v),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey('entity-$_entityFilter'),
                      initialValue: _entityFilter,
                      decoration: const InputDecoration(
                        labelText: 'Entity type',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All types')),
                        for (final t in sortedEntities)
                          DropdownMenuItem<String?>(value: t, child: Text(t)),
                      ],
                      onChanged: (v) => setState(() => _entityFilter = v),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _from ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) setState(() => _from = d);
                    },
                    icon: const Icon(Icons.date_range),
                    label: Text(_from == null ? 'From date' : _fmt.format(_from!)),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _to ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) setState(() => _to = d);
                    },
                    icon: const Icon(Icons.date_range),
                    label: Text(_to == null ? 'To date' : _fmt.format(_to!)),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _from = null;
                      _to = null;
                    }),
                    child: const Text('Clear dates'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '${filtered.length} events (showing ${page.length})',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final row in page) _LogTile(row: row, fmt: _fmt),
              if (filtered.length > _pageSize)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PillrButton(
                      label: 'Show more (filtered)',
                      variant: PillrButtonVariant.ghost,
                      onPressed: () => setState(() => _pageSize += 20),
                    ),
                  ),
                ),
              if (_hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PillrButton(
                      label: _loadingMore ? 'Loading…' : 'Load more from server',
                      variant: PillrButtonVariant.secondary,
                      onPressed: _loadingMore ? null : _loadMore,
                    ),
                  ),
                ),
            ],
          ),
        ),
    );
  }

  Future<void> _exportPdf(List<ActivityLogRow> rows) async {
    final church = ref.read(churchNameProvider) ?? 'Church';
    final logoUrl = ref.read(churchSettingsProvider).valueOrNull?.logoUrl;
    final l10n = AppLocalizations.of(context);
    final profile = ref.read(churchUserProfileProvider).valueOrNull;
    final email = ref.read(firebaseAuthProvider).currentUser?.email;
    final exporter =
        (profile?.fullName.isNotEmpty == true) ? profile!.fullName : (email ?? '—');
    final when = DateFormat.yMMMd(Localizations.localeOf(context).toString()).add_Hm().format(DateTime.now());
    await shareTablePdf(
      title: 'Activity log export',
      subtitle: church,
      logoUrl: logoUrl,
      headers: const ['When', 'Actor', 'Action', 'Entity'],
      rows: [
        for (final r in rows)
          [
            _fmt.format(r.createdAt),
            r.actorName,
            r.action,
            '${r.entityType} ${r.entityId ?? ''}'.trim(),
          ],
      ],
      filename: 'pillr-activity-logs.pdf',
      generatedAtLine: l10n.pdfGeneratedAt(when),
      exporterLine: l10n.pdfExporter(exporter),
      footerBrand: l10n.pdfFooterBrand,
    );
  }

  void _exportCsv(List<ActivityLogRow> rows) {
    final buf = StringBuffer();
    buf.writeln('createdAt,actor,role,action,entityType,entityId');
    for (final r in rows) {
      final line = [
        r.createdAt.toIso8601String(),
        _csv(r.actorName),
        _csv(r.actorRole),
        _csv(r.action),
        _csv(r.entityType),
        _csv(r.entityId ?? ''),
      ].join(',');
      buf.writeln(line);
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV copied to clipboard.')),
    );
  }

  String _csv(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.row, required this.fmt});

  final ActivityLogRow row;
  final DateFormat fmt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.gray200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primaryLight,
                  child: Text(
                    row.actorName.isNotEmpty ? row.actorName[0].toUpperCase() : '?',
                    style: AppTypography.caption.copyWith(color: AppColors.primaryColor),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row.actorName} · ${row.actorRole}',
                        style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(fmt.format(row.createdAt), style: AppTypography.caption),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(describeActivityAction(row.action), style: AppTypography.body),
            const SizedBox(height: 4),
            Text(
              '${row.entityType}${row.entityId != null ? ' · ${row.entityId}' : ''}',
              style: AppTypography.caption.copyWith(color: AppColors.gray600),
            ),
            if (row.entityId != null) _EntityLink(row: row),
          ],
        ),
      ),
    );
  }

}

String describeActivityAction(String action) {
  switch (action) {
    case 'entry.create':
      return 'Created entry';
    case 'entry.update':
      return 'Updated entry';
    case 'entry.approve':
      return 'Approved entry';
    case 'entry.decline':
      return 'Declined entry';
    case 'partner.create':
      return 'Created partner';
    case 'partner.update':
      return 'Updated partner';
    case 'goal.create':
      return 'Created goal';
    case 'goal.update':
      return 'Updated goal';
    case 'goal.delete':
      return 'Deleted goal';
    case 'arm.create':
    case 'arm.update':
    case 'arm.delete':
    case 'arm.toggle':
      return 'Partnership arm change';
    case 'period.create':
    case 'period.update':
    case 'period.delete':
    case 'period.activate':
      return 'Partnership period change';
    default:
      return action;
  }
}

class _EntityLink extends StatelessWidget {
  const _EntityLink({required this.row});

  final ActivityLogRow row;

  @override
  Widget build(BuildContext context) {
    final id = row.entityId!;
    return switch (row.entityType) {
      'entry' => TextButton(
          onPressed: () => context.go('/entries/$id'),
          child: const Text('Open entry'),
        ),
      'partner' => TextButton(
          onPressed: () => context.go('/partners/$id'),
          child: const Text('Open partner'),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}
