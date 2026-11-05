import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
import '../features/arms/providers/arms_providers.dart';
import '../l10n/app_localizations.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/domain/partnership_entry.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/partners/domain/partner.dart';
import '../features/leaderboard/giving_view.dart';
import '../features/partners/providers/partners_providers.dart';
import '../features/shortcuts/shortcuts.dart';

/// Global search across fellowships, partners, entries and pages.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _q = TextEditingController();
  List<Partner> _partners = [];
  List<PartnershipEntry> _entries = [];
  bool _busy = false;
  bool _ran = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Timer? _debounce;
  int _seq = 0;

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _run);
  }

  /// Runs the current query.
  ///
  /// Every run carries a sequence number and a slow answer to an old query is
  /// dropped: typing "Kwe" then "Kweku" must not end with the results for
  /// "Kwe" landing last.
  Future<void> _run() async {
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) return;
    final query = _q.text.trim();
    final seq = ++_seq;

    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        _error = null;
        _partners = [];
        _entries = [];
        _busy = false;
        _ran = query.isNotEmpty;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Staff see the entries they recorded; a pastor sees the church's.
      final partnersFuture = ref
          .read(partnersRepositoryProvider)
          .searchPartners(idx.churchId, query);
      final pageFuture = ref
          .read(entriesRepositoryProvider)
          .fetchEntriesPage(
            idx.churchId,
            allChurchEntries: idx.isPastor,
            createdByUid: idx.isPastor ? null : idx.uid,
            pageSize: 80,
          );
      final partners = await partnersFuture;
      final page = await pageFuture;
      if (!mounted || seq != _seq) return;

      final lower = query.toLowerCase();
      final entries = page.items.where((e) {
        final name =
            e.partnerSnapshot['fullName']?.toString().toLowerCase() ?? '';
        final memberId =
            e.partnerSnapshot['memberId']?.toString().toLowerCase() ?? '';
        return name.contains(lower) ||
            memberId.contains(lower) ||
            e.status.toLowerCase().contains(lower);
      }).toList();

      setState(() {
        _partners = partners;
        _entries = entries;
        _busy = false;
        _ran = true;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final money = ref.watch(churchMoneyFormatProvider);
    final tree = ref.watch(armTreeProvider);
    final q = _q.text.trim().toLowerCase();
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final view = ref.watch(givingViewProvider);
    final fellowships = q.length < 2
        ? const []
        : view.fellowships.where((f) => f.name.toLowerCase().contains(q)).toList();
    final pages = q.length < 2
        ? const <(String, String, String)>[]
        : [
            for (final s in shortcutsFor(isPastor: idx?.isPastor ?? false))
              if (s.label.toLowerCase().contains(q)) (s.label, s.group, s.path),
            for (final f in fellowships)
              for (final (tab, label) in const [
                ('people', 'People'),
                ('arms', 'Arms'),
                ('months', 'Month by month'),
              ])
                (
                  '${f.name} · $label',
                  'Fellowships › ${f.name}',
                  '/fellowships/${Uri.encodeComponent(f.key)}?tab=$tab',
                ),
          ];

    String initials(String n) => n
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    final groups = <(String, List<_Hit>)>[
      if (_ran)
        ('Partners', [
          for (final p in _partners)
            _Hit(
              lead: _Lead.text(initials(p.fullName)),
              title: p.fullName,
              sub: [p.memberId, p.fellowship].where((e) => e.isNotEmpty).join(' · '),
              mono: true,
              go: '/partners/${p.id}',
            ),
        ]),
      if (_ran)
        ('Entries', [
          for (final e in _entries)
            _Hit(
              lead: _Lead.text('₵', muted: true),
              title:
                  '${money(e.amountCedis)} · ${tree.shownNameOf(e.partnershipArmId) ?? e.armSnapshot['name'] ?? ''}',
              sub:
                  '${e.partnerSnapshot['fullName'] ?? '—'} · ${formatFirestoreDate(e.dateGiven, pattern: 'd MMM')}',
              trailing: SelStatusMark.fromString(
                status: e.status,
                label: switch (e.status) {
                  'approved' => 'Approved',
                  'pending' => 'Waiting',
                  'declined' => 'Sent back',
                  _ => e.status[0].toUpperCase() + e.status.substring(1),
                },
              ),
              go: '/entries/${e.id}',
            ),
        ]),
      ('Fellowships', [
        for (final f in fellowships)
          _Hit(
            lead: _Lead.icon(LucideIcons.users),
            title: f.name,
            sub: '${f.partners} partners · ${money(f.total)} this period',
            go: '/fellowships/${Uri.encodeComponent(f.key)}',
          ),
      ]),
      ('Pages', [
        for (final (label, where, path) in pages)
          _Hit(
            lead: _Lead.icon(LucideIcons.fileText),
            title: label,
            sub: where,
            go: path,
          ),
      ]),
      if (_ran && _partners.length == 1 && (idx?.isPastor == true || idx?.isStaff == true))
        ('Do something', [
          _Hit(
            lead: _Lead.icon(LucideIcons.plus, strong: true),
            title: 'Record giving for ${_partners.first.fullName}',
            sub: 'Opens the form',
            go: '/entries/new',
          ),
        ]),
    ].where((g) => g.$2.isNotEmpty).toList();
    final first = groups.isEmpty ? null : groups.first.$2.first;

    return SelPageBody(
      maxWidth: 800,
      children: [
        SelPageTitle(
          title: l10n.titleSearch,
          subtitle: 'Find a partner, an entry, a fellowship or a page.',
        ),
        SelCard(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // No Search button: results that arrive as you type tell you
              // whether to keep going.
              SelField(
                controller: _q,
                hint: l10n.searchFieldHint,
                prefixIcon: LucideIcons.search,
                autofocus: true,
                onChanged: _onChanged,
                onSubmitted: (_) =>
                    first == null ? _run() : context.go(first.go),
                suffixIcon: _busy
                    ? const Padding(
                        padding: EdgeInsets.only(right: SelSpace.x3),
                        child: PillrLoader(size: 18),
                      )
                    : null,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(SelSpace.x3),
                  child: Text(_error!, style: SelType.bodySm.copyWith(color: Sel.ink)),
                ),
              if (!_ran && q.length < 2)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
                  child: Text(
                    'Type a name, a member ID, a fellowship or a page. Results appear as you go.',
                    style: SelType.bodySm,
                  ),
                )
              else if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
                  child: Text(
                    'Nothing matches “${_q.text.trim()}”. Try a different spelling or a member ID.',
                    style: SelType.bodySm,
                  ),
                ),
              for (final (label, hits) in groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
                  child: Text('$label · ${hits.length}', style: SelType.small),
                ),
                for (final h in hits)
                  _HitRow(hit: h, query: q, first: identical(h, first)),
              ],
              const Divider(height: 24, color: Sel.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Row(
                  children: [
                    Text('Enter opens the first result', style: SelType.small),
                    const Spacer(),
                    Text(
                      'Also finds old member IDs and phone numbers',
                      style: SelType.small,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Lead {
  const _Lead.text(this.text, {this.muted = false})
    : icon = null,
      strong = false;
  const _Lead.icon(this.icon, {this.strong = false})
    : text = null,
      muted = false;

  final String? text;
  final IconData? icon;
  final bool muted;
  final bool strong;
}

class _Hit {
  const _Hit({
    required this.lead,
    required this.title,
    required this.sub,
    required this.go,
    this.trailing,
    this.mono = false,
  });

  final _Lead lead;
  final String title;
  final String sub;
  final String go;
  final Widget? trailing;
  final bool mono;
}

class _HitRow extends StatelessWidget {
  const _HitRow({required this.hit, required this.query, required this.first});

  final _Hit hit;
  final String query;
  final bool first;

  /// The matched part of [text] on a light-sky ground.
  InlineSpan _marked(String text, TextStyle style) {
    final at = query.isEmpty ? -1 : text.toLowerCase().indexOf(query);
    if (at < 0) return TextSpan(text: text, style: style);
    return TextSpan(
      style: style,
      children: [
        TextSpan(text: text.substring(0, at)),
        TextSpan(
          text: text.substring(at, at + query.length),
          style: const TextStyle(backgroundColor: Sel.skyWash),
        ),
        TextSpan(text: text.substring(at + query.length)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = hit.lead;
    return Material(
      color: first ? Sel.skyTint : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go(hit.go),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: l.strong
                      ? Sel.ink
                      : l.muted || l.icon != null
                      ? Sel.track
                      : Sel.skyWash,
                  shape: BoxShape.circle,
                ),
                child: l.icon != null
                    ? Icon(l.icon, size: 15, color: l.strong ? Sel.card : Sel.ink)
                    : Text(
                        l.text!,
                        style: SelType.small.copyWith(
                          color: Sel.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              const SizedBox(width: SelSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      _marked(
                        hit.title,
                        SelType.body.copyWith(
                          color: Sel.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text.rich(_marked(hit.sub, SelType.small)),
                  ],
                ),
              ),
              if (hit.trailing != null) hit.trailing!,
              if (first && hit.trailing == null)
                Text('Enter to open', style: SelType.small),
            ],
          ),
        ),
      ),
    );
  }
}

