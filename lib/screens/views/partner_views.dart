import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/extensions/async_value_ext.dart';
import '../../design/seline.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/church/providers/church_settings_providers.dart';
import '../../features/leaderboard/giving_view.dart';
import '../../features/partners/domain/partner.dart';
import '../../features/partners/providers/partners_providers.dart';
import '../../features/periods/providers/periods_providers.dart';
import 'view_common.dart';

String _phoneEnd(Partner p) {
  final digits = (p.phone ?? '').replaceAll(RegExp(r'\D'), '');
  return digits.length < 4
      ? 'None'
      : '··· ${digits.substring(digits.length - 4)}';
}

/// Partners · By fellowship: every partner, grouped under their fellowship.
/// Each group folds, so fifty fellowships stay a short list.
class PartnersByFellowshipScreen extends ConsumerStatefulWidget {
  const PartnersByFellowshipScreen({super.key});

  @override
  ConsumerState<PartnersByFellowshipScreen> createState() =>
      _PartnersByFellowshipState();
}

class _PartnersByFellowshipState
    extends ConsumerState<PartnersByFellowshipScreen> {
  String _query = '';
  final Set<String> _open = {};
  bool _openedFirst = false;

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(churchMoneyFormatProvider);
    final view = ref.watch(givingViewProvider);
    final roster = ref.watch(partnersStreamProvider(false));
    final givingOf = {for (final p in view.partners) p.partnerId: p.total};

    return SelPageBody(
      children: [
        SelPageTitle(
          title: 'Partners by fellowship',
          subtitle: '${view.fellowships.length} fellowships',
          actions: [
            SelButton(
              label: 'Open all',
              kind: SelButtonKind.quiet,
              dense: true,
              onPressed: () => setState(
                () => _open.addAll(view.fellowships.map((f) => f.key)),
              ),
            ),
            SelButton(
              label: 'Close all',
              kind: SelButtonKind.quiet,
              dense: true,
              onPressed: () => setState(_open.clear),
            ),
          ],
        ),
        ViewSearch(
          hint: 'Name or phone',
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: SelSpace.x4),
        roster.when(
          loading: () => const ViewLoading(),
          error: (e, _) => SelError(message: '$e'),
          data: (partners) {
            final groups = <String, List<Partner>>{};
            for (final p in partners) {
              final hit =
                  _query.isEmpty ||
                  p.fullName.toLowerCase().contains(_query) ||
                  (p.phone ?? '').contains(_query);
              if (hit) {
                groups
                    .putIfAbsent(p.fellowship.trim().toLowerCase(), () => [])
                    .add(p);
              }
            }
            if (!_openedFirst && view.fellowships.isNotEmpty) {
              _openedFirst = true;
              _open.add(view.fellowships.first.key);
            }
            final order = view.fellowships.where(
              (f) => groups.containsKey(f.key),
            );
            if (order.isEmpty) {
              return SelCard(
                child: SelEmpty(
                  title: _query.isEmpty ? 'No partners yet' : 'No matches',
                  message: _query.isEmpty
                      ? 'Add partners to see them by fellowship.'
                      : 'Nothing matches “$_query”.',
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in order) ...[
                  _Fold(
                    title: f.name,
                    meta: '${f.partners} partners',
                    trailing: money(f.total),
                    open: _open.contains(f.key) || _query.isNotEmpty,
                    onToggle: () => setState(
                      () => _open.contains(f.key)
                          ? _open.remove(f.key)
                          : _open.add(f.key),
                    ),
                    child: SelLedger(
                      minWidth: 480,
                      columns: const [
                        SelColumn('Partner', flex: 3),
                        SelColumn.numeric('Giving this year', width: 160),
                        SelColumn.numeric('Phone', width: 110),
                      ],
                      rows: [
                        for (final p
                            in (groups[f.key]!..sort(
                              (a, b) => (givingOf[b.id] ?? 0).compareTo(
                                givingOf[a.id] ?? 0,
                              ),
                            )))
                          SelRow(
                            onTap: () => context.go('/partners/${p.id}'),
                            cells: [
                              SelCell.primary(p.fullName),
                              SelCell.numeric(money(givingOf[p.id] ?? 0)),
                              SelCell.numeric(_phoneEnd(p), strong: false),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SelSpace.x3),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// A card whose header opens and closes its body.
class _Fold extends StatelessWidget {
  const _Fold({
    required this.title,
    required this.meta,
    required this.trailing,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String meta;
  final String trailing;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SelSpace.x4),
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: open ? 0.25 : 0,
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        child: const Icon(
                          LucideIcons.chevronRight,
                          size: 18,
                          color: Sel.ink,
                        ),
                      ),
                      const SizedBox(width: SelSpace.x3),
                      Text(title, style: SelType.bodyMedium),
                      const SizedBox(width: SelSpace.x2),
                      Text(meta, style: SelType.small),
                      const Spacer(),
                      Text(trailing, style: SelType.bodyMedium),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SelSpace.x4,
                0,
                SelSpace.x4,
                SelSpace.x3,
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// Partners · New this year: partners added since the period began, and
/// whether they have given yet.
class NewPartnersScreen extends ConsumerWidget {
  const NewPartnersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(churchMoneyFormatProvider);
    final view = ref.watch(givingViewProvider);
    final period = ref.watch(activePeriodProvider);
    final roster = ref.watch(partnersStreamProvider(false));
    final byId = {for (final p in view.partners) p.partnerId: p};
    final since = period?.startDate ?? DateTime(DateTime.now().year);

    return SelPageBody(
      children: [
        SelPageTitle(
          title: 'New this year',
          subtitle: 'Partners added since ${gaveOn(since)}, newest first.',
        ),
        roster.when(
          loading: () => const ViewLoading(),
          error: (e, _) => SelError(message: '$e'),
          data: (partners) {
            final fresh =
                partners.where((p) => !p.createdAt.isBefore(since)).toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return SelLedger(
              minWidth: 640,
              columns: const [
                SelColumn('Partner', flex: 3),
                SelColumn('Fellowship', flex: 2),
                SelColumn('Added', fit: SelColFit.fixed, width: 110),
                SelColumn('First gave', fit: SelColFit.fixed, width: 110),
                SelColumn.numeric('Given', width: 140),
              ],
              emptyState: const SelEmpty(
                title: 'No new partners yet',
                message: 'Partners added in this period show up here.',
                icon: LucideIcons.userPlus,
              ),
              rows: [
                for (final p in fresh)
                  SelRow(
                    onTap: () => context.go('/partners/${p.id}'),
                    cells: [
                      SelCell.primary(p.fullName),
                      SelCell.secondary(p.fellowship),
                      SelCell.secondary(gaveOn(p.createdAt)),
                      SelCell.secondary(gaveOn(byId[p.id]?.firstGave)),
                      SelCell.numeric(
                        byId[p.id] == null ? '–' : money(byId[p.id]!.total),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Partners · Giving rhythm: one dot per month, filled when the partner gave.
class GivingRhythmScreen extends ConsumerStatefulWidget {
  const GivingRhythmScreen({super.key});

  @override
  ConsumerState<GivingRhythmScreen> createState() => _GivingRhythmState();
}

class _GivingRhythmState extends ConsumerState<GivingRhythmScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(givingViewProvider);
    final loading = ref.watch(givingViewLoadingProvider);
    final months = view.months.length > 12
        ? view.months.sublist(view.months.length - 12)
        : view.months;
    final rows = view.partners
        .where((p) => _query.isEmpty || p.name.toLowerCase().contains(_query))
        .toList();

    return SelPageBody(
      children: [
        const SelPageTitle(
          title: 'Giving rhythm',
          subtitle:
              'Which months each partner gave in. A filled dot means they gave.',
        ),
        ViewSearch(
          hint: 'Find a partner',
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: SelSpace.x4),
        if (loading)
          const ViewLoading()
        else
          SelLedger.builder(
            minWidth: 260.0 + months.length * 40 + 90,
            maxVirtualHeight: 720,
            columns: [
              const SelColumn('Partner', flex: 3),
              for (final m in months)
                SelColumn(
                  monthShort(m),
                  fit: SelColFit.fixed,
                  width: 40,
                  align: TextAlign.center,
                ),
              const SelColumn.numeric('Months', width: 90),
            ],
            emptyState: const SelEmpty(
              title: 'No giving yet',
              message: 'Partners appear here once their giving is approved.',
            ),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final p = rows[i];
              final gave = months.where((m) => (p.byMonth[m] ?? 0) > 0).length;
              return SelRow(
                onTap: () => context.go('/partners/${p.partnerId}'),
                cells: [
                  SelCell.stacked(p.name, p.fellowship),
                  for (final m in months)
                    Center(child: _Dot(on: (p.byMonth[m] ?? 0) > 0)),
                  SelCell.numeric('$gave of ${months.length}', strong: false),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: on ? Sel.ink : Sel.card,
      border: Border.all(color: on ? Sel.ink : Sel.borderMuted, width: 1.5),
    ),
  );
}

/// Partners · Follow up: active partners who have not given in a while, with
/// a reason the church can note against each one.
class FollowUpScreen extends ConsumerStatefulWidget {
  const FollowUpScreen({super.key});

  @override
  ConsumerState<FollowUpScreen> createState() => _FollowUpState();
}

class _FollowUpState extends ConsumerState<FollowUpScreen> {
  int _days = 60;

  Future<void> _editReason(Partner p) async {
    final ctrl = TextEditingController(text: p.followUpReason ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reason for ${p.fullName}'),
        content: SizedBox(
          width: 420,
          child: SelField(
            controller: ctrl,
            hint: 'Called 12 Oct, travelling',
            autofocus: true,
            onSubmitted: (_) => Navigator.pop(context, true),
          ),
        ),
        actions: [
          SelButton(
            label: 'Cancel',
            kind: SelButtonKind.quiet,
            onPressed: () => Navigator.pop(context, false),
          ),
          SelButton.cyan(
            label: 'Save',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (save != true || idx == null) return;
    await ref
        .read(partnersRepositoryProvider)
        .setFollowUpReason(
          churchId: idx.churchId,
          partnerId: p.id,
          reason: ctrl.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(givingViewProvider);
    final roster = ref.watch(partnersStreamProvider(false));
    final lastOf = {for (final p in view.partners) p.partnerId: p.lastGave};
    final cutoff = DateTime.now().subtract(Duration(days: _days));

    return SelPageBody(
      children: [
        SelPageTitle(
          title: 'Follow up',
          subtitle: "Active partners who haven't given in $_days days.",
        ),
        SelPillGroup<int>(
          selected: _days,
          onChanged: (v) => setState(() => _days = v),
          options: const [(60, '60 days'), (90, '90 days'), (180, '6 months')],
        ),
        const SizedBox(height: SelSpace.x4),
        roster.when(
          loading: () => const ViewLoading(),
          error: (e, _) => SelError(message: '$e'),
          data: (partners) {
            final quiet =
                partners.where((p) {
                  if (!p.isActive) return false;
                  final last = lastOf[p.id];
                  return last == null || last.isBefore(cutoff);
                }).toList()..sort((a, b) {
                  final la = lastOf[a.id], lb = lastOf[b.id];
                  if (la == null) return lb == null ? 0 : 1;
                  if (lb == null) return -1;
                  return la.compareTo(lb);
                });
            return SelLedger(
              minWidth: 760,
              columns: const [
                SelColumn('Partner', flex: 3),
                SelColumn('Fellowship', flex: 2),
                SelColumn('Last gave', fit: SelColFit.fixed, width: 120),
                SelColumn.numeric('Phone', width: 110),
                SelColumn('Reason', flex: 3),
              ],
              emptyState: const SelEmpty(
                title: 'Everyone has given recently',
                message: 'Nobody needs a call right now.',
                icon: LucideIcons.phoneCall,
              ),
              rows: [
                for (final p in quiet)
                  SelRow(
                    onTap: () => context.go('/partners/${p.id}'),
                    cells: [
                      SelCell.primary(p.fullName),
                      SelCell.secondary(p.fellowship),
                      SelCell.secondary(gaveOn(lastOf[p.id])),
                      SelCell.numeric(_phoneEnd(p), strong: false),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelButton(
                          label: p.followUpReason?.trim().isNotEmpty == true
                              ? p.followUpReason!
                              : 'Add a reason',
                          kind: SelButtonKind.quiet,
                          dense: true,
                          onPressed: () => _editReason(p),
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
