import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/date_utils.dart';
import '../features/activity/activity_action_label.dart';
import '../features/activity/domain/activity_log_row.dart';
import '../core/utils/text_case_utils.dart';
import '../design/seline.dart';
import '../features/activity/providers/activity_log_providers.dart';
import '../features/auth/providers/auth_providers.dart';

enum _Kind { everything, giving, partners, repairs, settings }

/// Activity — the church's audit trail, as on the canvas: a search, kinds as
/// pills, and the changes grouped by day with who made them and what changed.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _search = TextEditingController();
  _Kind _kind = _Kind.everything;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _ofKind(ActivityLogRow r) => switch (_kind) {
    _Kind.everything => true,
    _Kind.giving =>
      r.action.startsWith('entry.') || r.action.startsWith('import.'),
    _Kind.partners =>
      r.action.startsWith('partner.') && r.action != 'partner.tidy' ||
          r.action.startsWith('fellowship.'),
    _Kind.repairs =>
      r.action.startsWith('totals.') || r.action == 'partner.tidy',
    _Kind.settings => r.action.startsWith('settings.'),
  };

  /// Search finds who did something, never what it was done to: the log
  /// is read by admins, who see no partner and no figure.
  bool _matches(ActivityLogRow r, String q) =>
      q.isEmpty || r.actorName.toLowerCase().contains(q);

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    if (idx == null) return const SizedBox.shrink();
    final logs = ref.watch(activityLogsFullProvider);
    final q = _search.text.trim().toLowerCase();

    Widget pill(_Kind k, String label) => Padding(
      padding: const EdgeInsets.only(left: SelSpace.x2),
      child: Material(
        color: _kind == k ? Sel.ink : Sel.card,
        shape: StadiumBorder(
          side: BorderSide(color: _kind == k ? Sel.ink : Sel.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setState(() => _kind = k),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Text(
              label,
              style: SelType.bodySm.copyWith(
                color: _kind == k ? Sel.card : Sel.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );

    return SelPageBody(
      onRefresh: () async => ref.invalidate(activityLogsFullProvider),
      children: [
        const SelPageTitle(
          title: 'Activity',
          subtitle:
              'Who did what, most recent first. It says what kind of change it was, never who it was for or how much.',
        ),
        Wrap(
          runSpacing: SelSpace.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 320,
              child: SelField(
                controller: _search,
                hint: 'Search by who did it',
                prefixIcon: LucideIcons.search,
                onChanged: (_) => setState(() {}),
              ),
            ),
            pill(_Kind.everything, 'Everything'),
            pill(_Kind.giving, 'Giving'),
            pill(_Kind.partners, 'Partners'),
            pill(_Kind.repairs, 'Repairs'),
            pill(_Kind.settings, 'Church settings'),
          ],
        ),
        const SizedBox(height: SelSpace.x4),
        logs.when(
          loading: () => const SelCard(child: SelSkeletonRows(count: 8)),
          error: (e, _) => SelError(message: '$e'),
          data: (all) {
            final rows = [
              for (final r in all)
                if (_ofKind(r) && _matches(r, q)) r,
            ];
            if (rows.isEmpty) {
              return const SelCard(
                child: SelEmpty(
                  title: 'Nothing logged yet',
                  message: 'Changes your team makes will be listed here.',
                  icon: LucideIcons.history,
                ),
              );
            }
            final today = DateTime.now();
            String dayLabel(DateTime d) {
              final day = DateTime(d.year, d.month, d.day);
              final diff = DateTime(today.year, today.month, today.day)
                  .difference(day)
                  .inDays;
              final full = formatFirestoreDate(d, pattern: 'EEEE, d MMMM');
              if (diff == 0) {
                return 'Today, ${formatFirestoreDate(d, pattern: 'd MMMM')}';
              }
              if (diff == 1) {
                return 'Yesterday, ${formatFirestoreDate(d, pattern: 'd MMMM')}';
              }
              return d.year == today.year
                  ? full
                  : formatFirestoreDate(d, pattern: 'EEEE, d MMMM y');
            }

            final children = <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: _Line(
                  when: Text('When', style: SelType.small),
                  who: Text('Who', style: SelType.small),
                  what: Text('Did what', style: SelType.small),
                  on: Text('On', style: SelType.small),
                ),
              ),
            ];
            String? lastDay;
            for (final r in rows) {
              final label = dayLabel(r.createdAt);
              if (label != lastDay) {
                lastDay = label;
                children
                  ..add(const Divider(height: 1, color: Sel.rowLine))
                  ..add(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                      child: Text(
                        label,
                        style: SelType.small.copyWith(
                          color: Sel.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
              }
              children
                ..add(const Divider(height: 1, color: Sel.rowLine))
                ..add(_ActivityRow(row: r));
            }
            return SelCard(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.when,
    required this.who,
    required this.what,
    required this.on,
  });

  final Widget when;
  final Widget who;
  final Widget what;
  final Widget on;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 76, child: when),
      SizedBox(width: 180, child: who),
      Expanded(child: what),
      const SizedBox(width: SelSpace.x4),
      SizedBox(width: 160, child: on),
    ],
  );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.row});

  final ActivityLogRow row;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final name = TextCaseUtils.toTitleCase(r.actorName);
    final words = name.split(' ').where((w) => w.isNotEmpty);
    final role = r.actorRole.toLowerCase();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: _Line(
        when: Text(
          formatFirestoreDate(r.createdAt, pattern: 'HH:mm'),
          style: SelType.bodySm.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        who: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: role == 'pastor'
                    ? Sel.ink
                    : role == 'staff'
                    ? Sel.skyWash
                    : Sel.track,
                shape: BoxShape.circle,
              ),
              child: Text(
                words.take(2).map((w) => w[0].toUpperCase()).join(),
                style: SelType.small.copyWith(
                  color: role == 'pastor' ? Sel.card : Sel.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: SelSpace.x2),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: SelType.body.copyWith(color: Sel.text),
              ),
            ),
          ],
        ),
        what: Text(
          activityActionLabel(r.action),
          style: SelType.body.copyWith(color: Sel.text),
        ),
        on: Text(_activityOn(r), style: SelType.bodySm),
      ),
    );
  }
}

/// What kind of thing changed, never which one: no partner, fellowship or
/// period name, and no amount.
String _activityOn(ActivityLogRow r) => switch (r.entityType) {
  'entry' => 'Giving',
  'partner' => 'Partner',
  'fellowship' => 'Fellowship',
  'import' => 'A sheet',
  'settings' || 'church' => 'Church',
  'arm' || 'partnership_arm' => 'Arm',
  'period' || 'partnership_period' => 'Period',
  final t when t.isEmpty => 'Church',
  final t => t[0].toUpperCase() + t.substring(1).replaceAll('_', ' '),
};

/// Full log, distinct from the short dashboard preview.
final activityLogsFullProvider = StreamProvider.autoDispose((ref) {
  final idx = ref.watch(userChurchIndexProvider).valueOrNull;
  if (idx == null) return Stream.value([]);
  return ref
      .watch(activityLogRepositoryProvider)
      .watchActivityLogs(idx.churchId, limit: 200);
});
