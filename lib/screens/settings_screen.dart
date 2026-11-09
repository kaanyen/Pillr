import 'dart:ui' as ui;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../core/errors/plain_error.dart';
import '../core/extensions/async_value_ext.dart';
import '../core/notifications/sel_notice.dart';
import '../core/providers/locale_provider.dart';
import '../design/seline.dart';
import '../features/activity/activity_log_helper.dart';
import '../features/auth/domain/church_user.dart';
import '../features/auth/domain/user_church_index.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/data/church_settings_repository.dart';
import '../features/church/domain/church_settings.dart';
import '../features/church/domain/exchange_rates.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/users/providers/users_providers.dart';

const _kPrefDigest = 'pillr_notify_daily_digest';
const _kPrefGoals = 'pillr_notify_goal_milestones';

final notificationDigestProvider = FutureProvider<bool>((ref) async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(_kPrefDigest) ?? true;
});

final notificationGoalsProvider = FutureProvider<bool>((ref) async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(_kPrefGoals) ?? true;
});

enum SettingsTab { church, letters, money, notifications, account }

const _tabLabels = {
  SettingsTab.church: 'Church',
  SettingsTab.letters: 'Letters',
  SettingsTab.money: 'Money',
  SettingsTab.notifications: 'Notifications',
  SettingsTab.account: 'Your account',
};

/// The tabs a role sees. Staff have no say over the church or its letters.
List<SettingsTab> settingsTabsFor(UserChurchIndex? idx) {
  if (idx == null) return const [SettingsTab.account];
  if (idx.isStaff) return const [SettingsTab.money, SettingsTab.notifications, SettingsTab.account];
  return SettingsTab.values;
}

/// The church colours on offer, with names so they are never colour alone.
const _colours = [
  ('#13426F', 'Navy'),
  ('#1F6F4A', 'Green'),
  ('#7A2440', 'Wine'),
  ('#B4532A', 'Clay'),
  ('#333333', 'Charcoal'),
];

/// Words a letter fills in for each partner.
const _tokens = ['[First name]', '[Month]', '[Church name]'];

const _defaultWording = (
  subject: 'Your [Month] giving to [Church name]',
  heading: 'Thank you, [First name].',
  message:
      'Here is your giving for [Month]. Every cedi goes to the work you gave it for, and we are grateful for each one.',
  signOff: 'With gratitude,',
);

Color? _hex(String? hex) {
  final h = (hex ?? '').replaceAll('#', '').trim();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

String _initials(String name) => name
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w[0].toUpperCase())
    .join();

/// Settings, as on the canvas (boards 58–63): tabs across the top, each
/// setting a row with what it is on the left and the control on the right,
/// and one way to save — the pinned bar — on every tab that has a form.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.initialTab});

  /// From `?tab=`, so a link can open a tab.
  final String? initialTab;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static SettingsTab? _lastTab; // remembered while the app is open
  SettingsTab? _tab;
  bool _busy = false;
  bool _seeded = false;

  // Church
  final _name = TextEditingController();
  String _colour = '';
  ({String url, String? path})? _removedLogo;

  // Letters
  bool _lettersOn = false;
  String? _pastorUid;
  final _from = TextEditingController();
  final _subject = TextEditingController();
  final _heading = TextEditingController();
  final _message = TextEditingController();
  final _signOff = TextEditingController();
  final _focus = {for (final k in ['subject', 'heading', 'message', 'signOff']) k: FocusNode()};
  String _focused = 'message';

  // Money
  final _rates = {
    SelectableCurrency.usd: TextEditingController(),
    SelectableCurrency.eur: TextEditingController(),
    SelectableCurrency.gbp: TextEditingController(),
  };

  // Notifications: which switch just saved
  String? _savedSwitch;

  List<TextEditingController> get _controllers =>
      [_name, _from, _subject, _heading, _message, _signOff, ..._rates.values];

  @override
  void initState() {
    super.initState();
    _tab = SettingsTab.values.where((t) => t.name == widget.initialTab).firstOrNull ?? _lastTab;
    for (final e in _focus.entries) {
      e.value.addListener(() {
        if (e.value.hasFocus && mounted) setState(() => _focused = e.key);
      });
    }
    for (final c in _controllers) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(covariant SettingsScreen old) {
    super.didUpdateWidget(old);
    final t = SettingsTab.values.where((t) => t.name == widget.initialTab).firstOrNull;
    if (widget.initialTab != old.initialTab && t != null) _tab = _lastTab = t;
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _seed(ChurchSettings s) {
    _name.text = s.name ?? '';
    _colour = (s.primaryColorHex ?? '#13426F').toUpperCase();
    _lettersOn = s.sendMonthlyPartnerEmails;
    _pastorUid = s.primaryPastorUid;
    _from.text = s.partnerEmailFrom ?? '';
    _subject.text = s.letterSubject ?? _defaultWording.subject;
    _heading.text = s.letterHeading ?? _defaultWording.heading;
    _message.text = s.letterMessage ?? _defaultWording.message;
    _signOff.text = s.letterSignOff ?? _defaultWording.signOff;
    for (final e in _rates.entries) {
      final v = s.exchangeRates.ratesToBase[e.key];
      e.value.text = v == null ? '' : v.toStringAsFixed(2);
    }
  }

  // ------------------------------------------------------------ dirtiness

  bool _churchDirty(ChurchSettings s) =>
      _name.text.trim() != (s.name ?? '') ||
      _colour != (s.primaryColorHex ?? '#13426F').toUpperCase();

  bool _lettersDirty(ChurchSettings s) =>
      _lettersOn != s.sendMonthlyPartnerEmails ||
      _pastorUid != s.primaryPastorUid ||
      _from.text.trim() != (s.partnerEmailFrom ?? '') ||
      _subject.text.trim() != (s.letterSubject ?? _defaultWording.subject) ||
      _heading.text.trim() != (s.letterHeading ?? _defaultWording.heading) ||
      _message.text.trim() != (s.letterMessage ?? _defaultWording.message) ||
      _signOff.text.trim() != (s.letterSignOff ?? _defaultWording.signOff);

  bool _moneyDirty(ChurchSettings s) => _rates.entries.any((e) {
    final v = s.exchangeRates.ratesToBase[e.key];
    return e.value.text.trim() != (v == null ? '' : v.toStringAsFixed(2));
  });

  bool _dirty(SettingsTab t, ChurchSettings? s) =>
      s != null &&
      switch (t) {
        SettingsTab.church => _churchDirty(s),
        SettingsTab.letters => _lettersDirty(s),
        SettingsTab.money => _moneyDirty(s),
        _ => false,
      };

  String _changedWhat(SettingsTab t) => switch (t) {
    SettingsTab.church => 'You changed the church details',
    SettingsTab.letters => 'You changed the letters',
    SettingsTab.money => 'You changed the exchange rates',
    _ => '',
  };

  /// A rate's problem in plain words, or null when it is fine.
  String? _rateProblem(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'Enter a rate.';
    if (t.contains(',')) return 'Use a full stop for the decimal: ${t.replaceAll(',', '.')}.';
    final v = double.tryParse(t);
    if (v == null) return 'Use numbers only, like 15.40.';
    if (v <= 0) return 'The rate must be more than 0.';
    return null;
  }

  // ------------------------------------------------------------ saving

  Future<void> _save(SettingsTab t, ChurchSettings s, UserChurchIndex idx) async {
    final repo = ref.read(churchSettingsRepositoryProvider);
    if (t == SettingsTab.money && _rates.values.any((c) => _rateProblem(c.text) != null)) {
      selNotice(context, 'One of the rates needs fixing first.', kind: SelNoticeKind.error);
      return;
    }
    setState(() => _busy = true);
    try {
      switch (t) {
        case SettingsTab.church:
          await repo.updateBranding(
            churchId: s.churchId,
            name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            primaryColorHex: _colour,
          );
        case SettingsTab.letters:
          final pastors = _pastors(ref.read(churchUsersProvider).valueOrNull ?? const []);
          await repo.updateMonthlyPartnerEmail(
            churchId: s.churchId,
            enabled: _lettersOn,
            primaryPastorUid: _pastorUid ?? (pastors.length == 1 ? pastors.first.uid : null),
            partnerEmailFrom: _from.text,
            wording: _wording(),
          );
        case SettingsTab.money:
          final rates = ChurchExchangeRates(
            ratesToBase: {for (final e in _rates.entries) e.key: double.parse(e.value.text.trim())},
          );
          final me = ref.read(churchUserProfileProvider).valueOrNull?.fullName;
          await repo.updateExchangeRates(churchId: s.churchId, rates: rates, byName: me);
          await logPillrActivity(
            ref,
            churchId: s.churchId,
            action: 'settings.exchange_rates',
            entityType: 'church',
            entityId: s.churchId,
            entitySnapshot: {for (final e in rates.ratesToBase.entries) e.key: e.value},
          );
        default:
      }
      if (mounted) selNotice(context, 'Saved.');
    } catch (e) {
      if (mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  LetterWordingDraft _wording() => (
    subject: _subject.text.trim(),
    heading: _heading.text.trim(),
    message: _message.text.trim(),
    signOff: _signOff.text.trim(),
  );

  void _discard(ChurchSettings s) => setState(() => _seed(s));

  /// Leaving a tab with unsaved changes asks first.
  Future<void> _goTo(SettingsTab next, ChurchSettings? s, UserChurchIndex idx) async {
    final current = _tab ?? settingsTabsFor(idx).first;
    if (next == current) return;
    if (s != null && _dirty(current, s)) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => SelDialog(
          title: 'Save your changes first?',
          subtitle: '${_changedWhat(current)}. If you leave this tab now, the change is lost.',
          actions: [
            SelButton(label: 'Stay here', onPressed: () => Navigator.of(ctx).pop('stay')),
            SelButton(label: 'Discard', onPressed: () => Navigator.of(ctx).pop('discard')),
            SelButton.cyan(label: 'Save and go on', onPressed: () => Navigator.of(ctx).pop('save')),
          ],
          child: const SizedBox.shrink(),
        ),
      );
      if (choice == null || choice == 'stay' || !mounted) return;
      if (choice == 'save') {
        await _save(current, s, idx);
        if (!mounted) return;
        final fresh = ref.read(churchSettingsProvider).valueOrNull;
        if (fresh != null && _dirty(current, fresh)) return;
      } else {
        _discard(s);
      }
    }
    setState(() => _tab = _lastTab = next);
  }

  // ------------------------------------------------------------ logo

  Future<void> _uploadLogo(ChurchSettings s) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 1024 * 1024) {
      final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      selNotice(
        context,
        'That file is $mb MB. Choose one under 1 MB, or save it smaller and try again. Your current logo is unchanged.',
        kind: SelNoticeKind.error,
      );
      return;
    }
    final name = x.name.toLowerCase();
    final (ext, type) = name.endsWith('.png')
        ? ('png', 'image/png')
        : name.endsWith('.webp')
        ? ('webp', 'image/webp')
        : ('jpg', 'image/jpeg');
    setState(() => _busy = true);
    try {
      // How wide it is decides whether it reads in the sidebar.
      double? aspect;
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        aspect = frame.image.width / frame.image.height;
      } catch (_) {
        aspect = null;
      }
      final path = 'churches/${s.churchId}/branding/logo.$ext';
      final sref = FirebaseStorage.instance.ref(path);
      await sref.putData(bytes, SettableMetadata(contentType: type));
      final url = await sref.getDownloadURL();
      await ref.read(churchSettingsRepositoryProvider).updateBranding(
            churchId: s.churchId,
            logoUrl: url,
            logoStoragePath: path,
            logoAspect: aspect,
          );
      if (mounted) {
        setState(() => _removedLogo = null);
        selNotice(context, 'Logo uploaded.');
      }
    } catch (e) {
      if (mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeLogo(ChurchSettings s) async {
    final url = s.logoUrl;
    if (url == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(churchSettingsRepositoryProvider).removeLogo(s.churchId);
      if (mounted) setState(() => _removedLogo = (url: url, path: s.logoStoragePath));
    } catch (e) {
      if (mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undoRemoveLogo(ChurchSettings s) async {
    final r = _removedLogo;
    if (r == null) return;
    try {
      await ref.read(churchSettingsRepositoryProvider).restoreLogo(s.churchId, url: r.url, path: r.path);
      if (mounted) setState(() => _removedLogo = null);
    } catch (e) {
      if (mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
    }
  }

  // ------------------------------------------------------------ letters

  List<ChurchUser> _pastors(List<ChurchUser> users) =>
      [for (final u in users) if (u.role == 'pastor' && u.isActive) u];

  void _insert(String token) {
    final c = switch (_focused) {
      'subject' => _subject,
      'heading' => _heading,
      'signOff' => _signOff,
      _ => _message,
    };
    final sel = c.selection;
    final at = sel.isValid ? sel.start : c.text.length;
    final end = sel.isValid ? sel.end : c.text.length;
    final before = c.text.substring(0, at);
    final pad = before.isEmpty || before.endsWith(' ') ? '' : ' ';
    final text = '$pad$token';
    c.value = TextEditingValue(
      text: before + text + c.text.substring(end),
      selection: TextSelection.collapsed(offset: at + text.length),
    );
    _focus[_focused]?.requestFocus();
  }

  Future<void> _sendSample() async {
    setState(() => _busy = true);
    try {
      final to = await ref.read(churchSettingsRepositoryProvider).previewMonthlyPartnerEmail(wording: _wording());
      if (mounted) selNotice(context, to.isEmpty ? 'Sample sent.' : 'A sample is on its way to $to.');
    } catch (e) {
      if (mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------ money

  Future<void> _recalculate(ChurchSettings s) async {
    if (_moneyDirty(s)) {
      selNotice(context, 'Save the new rates first, then recalculate.', kind: SelNoticeKind.error);
      return;
    }
    final int count;
    try {
      count = await ref.read(entriesRepositoryProvider).countForeignEntries(s.churchId);
    } catch (e) {
      if (mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
      return;
    }
    if (!mounted) return;
    if (count == 0) {
      selNotice(context, 'No giving has been saved in dollars, euros or pounds, so there is nothing to recalculate.');
      return;
    }
    final ok = await selConfirm(
      context,
      title: 'Recalculate $count ${count == 1 ? 'entry' : 'entries'}?',
      message:
          'Each saved dollar, euro and pound entry is turned into cedis again at today\'s rates. '
          'What the partner gave stays the same; its cedi value and the church totals move.',
      confirmLabel: 'Recalculate $count',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await ref
          .read(entriesRepositoryProvider)
          .recalculateForeignEntries(churchId: s.churchId, rates: s.exchangeRates);
      ref.invalidate(rankingEntriesProvider);
      invalidateEntryDerivedData(ref);
      if (mounted) {
        selNotice(context, 'Done. ${r.updated} changed, ${r.unchanged} were already right.');
      }
    } catch (e) {
      if (mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _passwordReset() async {
    final email = ref.read(firebaseAuthProvider).currentUser?.email;
    if (email == null) return;
    try {
      await ref.read(firebaseAuthProvider).sendPasswordResetEmail(email: email);
      if (mounted) selNotice(context, 'A link to choose a new password is on its way to $email.');
    } catch (e) {
      if (mounted) selNotice(context, plainError(e), kind: SelNoticeKind.error);
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final settings = ref.watch(churchSettingsProvider).valueOrNull;
    if (settings != null && !_seeded) {
      _seeded = true;
      _seed(settings);
    }
    final tabs = settingsTabsFor(idx);
    final tab = tabs.contains(_tab) ? _tab! : tabs.first;
    final dirty = _dirty(tab, settings);

    final body = switch (tab) {
      SettingsTab.church => settings == null ? null : _churchTab(settings, idx),
      SettingsTab.letters => settings == null ? null : _lettersTab(settings),
      SettingsTab.money => settings == null ? null : _moneyTab(settings, idx),
      SettingsTab.notifications => _notificationsTab(),
      SettingsTab.account => _accountTab(idx),
    };

    return SelPageBody(
      bottomBar: dirty && settings != null && idx != null
          ? SelSaveBar(
              message: _changedWhat(tab),
              busy: _busy,
              onDiscard: () => _discard(settings),
              onSave: () => _save(tab, settings, idx),
            )
          : null,
      children: [
        SelPageTitle(
          title: 'Settings',
          subtitle: settings?.name == null
              ? 'How Pillr works for you.'
              : 'How ${settings!.name} appears, and how Pillr works for you.',
        ),
        if (tabs.length > 1) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: SelTrackTabs<SettingsTab>(
              selected: tab,
              onSelect: idx == null ? (_) {} : (t) => _goTo(t, settings, idx),
              tabs: [for (final t in tabs) (t, _tabLabels[t]!)],
            ),
          ),
          const SizedBox(height: SelSpace.x4),
        ],
        body ?? const SelCard(child: SelSkeletonRows(count: 4)),
      ],
    );
  }

  // ------------------------------------------------------------ church tab

  Widget _churchTab(ChurchSettings s, UserChurchIndex? idx) {
    final canEdit = idx?.isAdmin ?? false;
    final name = _name.text.trim().isEmpty ? (s.name ?? '') : _name.text.trim();
    final colour = _hex(_colour) ?? Sel.ink;
    final initials = _initials(name);

    Widget initialsBox(double w, double h, double font) => Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(h * 0.18)),
      child: Text(initials, style: SelType.hero.copyWith(fontSize: font, color: Sel.card)),
    );
    Widget logoImage(double w, double h) => Image.network(
      s.logoUrl!,
      width: w,
      height: h,
      fit: BoxFit.contain,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      errorBuilder: (_, _, _) => initialsBox(w, h, h * 0.36),
    );

    final logoBox = Container(
      width: 168,
      height: 124,
      padding: const EdgeInsets.all(12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Sel.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Sel.border, width: 1.5),
      ),
      child: s.logoUrl == null ? initialsBox(144, 100, 34) : logoImage(144, 100),
    );

    final swatches = Semantics(
      label: 'Church colour',
      child: Wrap(
        spacing: SelSpace.x3,
        runSpacing: SelSpace.x3,
        children: [
          for (final (hex, label) in [
            ..._colours,
            // A colour chosen before these five keeps showing, so it is not lost.
            if (_colours.every((c) => c.$1 != (s.primaryColorHex ?? '').toUpperCase()) && _hex(s.primaryColorHex) != null)
              ((s.primaryColorHex ?? '').toUpperCase(), 'Current'),
          ])
            Semantics(
              button: true,
              selected: _colour == hex,
              label: label,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _colour = hex),
                child: SizedBox(
                  width: 64,
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _hex(hex),
                          shape: BoxShape.circle,
                          border: _colour == hex ? Border.all(color: Sel.card, width: 3) : null,
                          boxShadow: _colour == hex ? const [BoxShadow(color: Sel.ink, spreadRadius: 2)] : null,
                        ),
                        child: _colour == hex ? const Icon(Icons.check_rounded, color: Sel.card, size: 22) : null,
                      ),
                      const SizedBox(height: 6),
                      Text(label, style: SelType.small.copyWith(color: Sel.text)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final sidebarFits = s.logoFitsSidebar;
    final preview = LayoutBuilder(
      builder: (context, c) {
        final sidebar = _PreviewPane(
          label: 'In the sidebar',
          note: s.logoUrl != null && !sidebarFits
              ? 'Your logo is wide, so the sidebar shows your initials in the church colour. A square logo shows there itself.'
              : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
            decoration: BoxDecoration(
              color: Sel.card,
              borderRadius: BorderRadius.circular(SelRadius.pill),
              border: Border.all(color: Sel.border),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 38,
                  height: 38,
                  child: s.logoUrl != null && sidebarFits ? logoImage(38, 38) : initialsBox(38, 38, 13),
                ),
                const SizedBox(width: SelSpace.x3),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: SelType.bodySm.copyWith(color: Sel.text, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
        final letter = _PreviewPane(
          label: 'On a letter or PDF',
          child: Row(
            children: [
              SizedBox(
                width: 72,
                height: 44,
                child: s.logoUrl == null ? initialsBox(44, 44, 15) : logoImage(72, 44),
              ),
              const SizedBox(width: SelSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: SelType.bodyMedium.copyWith(color: Sel.ink, fontWeight: FontWeight.w700)),
                    Text('Your October giving', style: SelType.small),
                  ],
                ),
              ),
            ],
          ),
        );
        return c.maxWidth < 520
            ? Column(children: [sidebar, const SizedBox(height: SelSpace.x3), letter])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: sidebar), const SizedBox(width: SelSpace.x3), Expanded(child: letter)],
              );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Rows([
          _Row(
            'Church name',
            'Shown in the sidebar, on letters to partners and on every PDF.',
            canEdit
                ? SelField(controller: _name, hint: 'Your church\'s name')
                : Text(s.name ?? '', style: SelType.body.copyWith(color: Sel.text)),
          ),
          _Row(
            'Logo',
            canEdit
                ? 'PNG or JPG, up to 1 MB. It always shows whole, never cropped.'
                : 'Your admin uploads and changes the logo.',
            Wrap(
              spacing: SelSpace.x6,
              runSpacing: SelSpace.x3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                logoBox,
                if (canEdit)
                  SelButton(
                    label: s.logoUrl == null ? 'Upload a logo' : 'Upload a new logo',
                    loading: _busy,
                    onPressed: _busy ? null : () => _uploadLogo(s),
                  ),
              ],
            ),
          ),
          if (canEdit)
            _Row(
              'Church colour',
              'Used for your initials when there is no logo, and for headings on letters and PDFs. Pillr itself stays blue.',
              swatches,
            ),
          _Row(
            'Preview',
            canEdit ? 'How the church will look once you save.' : 'How the church looks in Pillr.',
            preview,
          ),
        ]),
        const SizedBox(height: SelSpace.x4),
        _Rows([
          _Row(
            'Backups',
            'A full copy of Pillr every Sunday, kept for a year.',
            Align(
              alignment: Alignment.centerLeft,
              child: SelButton(label: 'Open Backups', onPressed: () => context.go('/backups')),
            ),
          ),
          if (canEdit && (s.logoUrl != null || _removedLogo != null))
            _Row(
              'Remove the logo',
              'Pillr goes back to your initials. You can undo this straight after.',
              Align(
                alignment: Alignment.centerLeft,
                child: _removedLogo != null
                    ? Wrap(
                        spacing: SelSpace.x3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Logo removed.', style: SelType.body.copyWith(color: Sel.ink)),
                          SelButton(label: 'Put it back', onPressed: () => _undoRemoveLogo(s)),
                        ],
                      )
                    : SelButton(label: 'Remove logo', onPressed: _busy ? null : () => _removeLogo(s)),
              ),
            ),
        ]),
      ],
    );
  }

  // ------------------------------------------------------------ letters tab

  Widget _lettersTab(ChurchSettings s) {
    final users = ref.watch(churchUsersProvider).valueOrNull ?? const <ChurchUser>[];
    final pastors = _pastors(users);
    final pastorValue = pastors.any((p) => p.uid == _pastorUid)
        ? _pastorUid
        : (pastors.length == 1 ? pastors.first.uid : null);
    final pastorName = pastors.where((p) => p.uid == pastorValue).firstOrNull?.fullName ?? 'Your pastor';
    final church = _name.text.trim().isEmpty ? (s.name ?? 'Your church') : _name.text.trim();
    String fill(String t) => t
        .replaceAll(RegExp(r'\[\s*first\s*name\s*\]', caseSensitive: false), 'Ama')
        .replaceAll(RegExp(r'\[\s*month\s*\]', caseSensitive: false), 'October')
        .replaceAll(RegExp(r'\[\s*church\s*name\s*\]', caseSensitive: false), church);
    String orDefault(TextEditingController c, String d) => c.text.trim().isEmpty ? d : c.text.trim();

    Widget insertRow(String field) => _focused != field
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: SelSpace.x2),
            child: Wrap(
              spacing: SelSpace.x2,
              runSpacing: SelSpace.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Add:', style: SelType.small),
                for (final t in _tokens)
                  SelButton(label: '+ ${t.substring(1, t.length - 1)}', dense: true, onPressed: () => _insert(t)),
              ],
            ),
          );

    Widget maybeDim(Widget w) => Opacity(opacity: _lettersOn ? 1 : 0.78, child: w);

    final letterPreview = Container(
      decoration: BoxDecoration(
        color: Sel.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Sel.border, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Sel.skyTint,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: Text.rich(
              TextSpan(
                style: SelType.bodySm.copyWith(color: Sel.text),
                children: [
                  const TextSpan(text: 'Subject   '),
                  TextSpan(
                    text: fill(orDefault(_subject, _defaultWording.subject)),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fill(orDefault(_heading, _defaultWording.heading)),
                  style: SelType.hero.copyWith(fontSize: 24, color: Sel.ink, height: 1.25),
                ),
                const SizedBox(height: SelSpace.x2),
                Text(fill(orDefault(_message, _defaultWording.message)), style: SelType.body.copyWith(color: Sel.text)),
                const SizedBox(height: SelSpace.x3),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Sel.skyTint, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Their giving for the month, by arm, and the year so far.',
                        style: SelType.bodySm.copyWith(color: Sel.ink),
                      ),
                      Text('Filled in by Pillr for each partner.', style: SelType.small),
                    ],
                  ),
                ),
                const SizedBox(height: SelSpace.x3),
                Text(fill(orDefault(_signOff, _defaultWording.signOff)), style: SelType.body.copyWith(color: Sel.text)),
                Text(pastorName, style: SelType.bodyMedium.copyWith(color: Sel.ink, fontWeight: FontWeight.w700)),
                Text(church, style: SelType.small),
              ],
            ),
          ),
        ],
      ),
    );

    Widget field(String key, TextEditingController c, int max, {int lines = 1}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelField(controller: c, focusNode: _focus[key], maxLength: max, maxLines: lines),
        if (lines > 1) ...[
          const SizedBox(height: 4),
          Text('${c.text.length} of $max characters', style: SelType.small),
        ],
        insertRow(key),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Rows([
          _Row(
            'Send monthly letters',
            _lettersOn
                ? 'On the 15th, every partner with an email gets a letter thanking them for the month before.'
                : 'Off. No letters go out on the 15th. Everything below is kept for when you switch them back on.',
            Align(
              alignment: Alignment.centerLeft,
              child: Switch(value: _lettersOn, onChanged: (v) => setState(() => _lettersOn = v)),
            ),
          ),
          _Row(
            'Signed by',
            'The primary pastor. Replies go to them.',
            maybeDim(
              pastors.isEmpty
                  ? Text(
                      'Letters need a pastor to sign them. Invite one from People, then choose them here.',
                      style: SelType.body.copyWith(color: Sel.ink, fontWeight: FontWeight.w700),
                    )
                  : SelSelect<String>(
                      value: pastorValue,
                      hint: const Text('Choose a pastor'),
                      onChanged: (v) => setState(() => _pastorUid = v),
                      items: [for (final p in pastors) DropdownMenuItem(value: p.uid, child: Text(p.fullName))],
                    ),
            ),
          ),
          _Row(
            'From address',
            'A mailbox on the church\'s own domain, like Partner Appreciation <giving@yourchurch.org>.',
            maybeDim(SelField(controller: _from, hint: 'Partner Appreciation <giving@yourchurch.org>')),
          ),
        ]),
        const SizedBox(height: SelSpace.x4),
        SelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('The letter', style: SelType.subtitle)),
                  SelLink(
                    label: 'Put back Pillr\'s wording',
                    onTap: () => setState(() {
                      _subject.text = _defaultWording.subject;
                      _heading.text = _defaultWording.heading;
                      _message.text = _defaultWording.message;
                      _signOff.text = _defaultWording.signOff;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: SelSpace.x1),
              Text(
                'Write it in your own words. [First name], [Month] and [Church name] are filled in for each partner. '
                'The giving figures are always added by Pillr, so they cannot be changed here.',
                style: SelType.bodySm,
              ),
              const SizedBox(height: SelSpace.x2),
              _Row('Subject', 'What partners see in their inbox. Keep it short.', field('subject', _subject, 150)),
              const Divider(height: 1, color: Sel.rowLine),
              _Row('Heading', 'The first line, in large letters.', field('heading', _heading, 120)),
              const Divider(height: 1, color: Sel.rowLine),
              _Row('Message', 'A few lines before the giving figures.', field('message', _message, 600, lines: 5)),
              const Divider(height: 1, color: Sel.rowLine),
              _Row('Sign-off', 'Above the pastor\'s name.', field('signOff', _signOff, 60)),
              const Divider(height: 1, color: Sel.rowLine),
              _Row('Preview', 'How a partner called Ama would see an October letter with your words.', letterPreview),
              const Divider(height: 1, color: Sel.rowLine),
              _Row(
                'Check it',
                'Sends you this letter, with your words as they are now and made-up figures.',
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelButton(label: 'Send me a sample', loading: _busy, onPressed: _busy ? null : _sendSample),
                ),
              ),
              const Divider(height: 1, color: Sel.rowLine),
              _Row(
                'Each month',
                'Who the letter reached, and any that could not be sent.',
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelButton(label: 'Open Monthly letters', onPressed: () => context.go('/settings/letters')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ money tab

  Widget _moneyTab(ChurchSettings s, UserChurchIndex? idx) {
    // Recalculating reads past entries, which admins do not read.
    final canRecalculate = idx != null && (idx.isPastor || idx.isStaff);
    const names = {
      SelectableCurrency.usd: 'US dollar',
      SelectableCurrency.eur: 'euro',
      SelectableCurrency.gbp: 'pound',
    };
    final changed = s.exchangeRatesUpdatedAt == null
        ? null
        : 'Last changed ${DateFormat('d MMM y').format(s.exchangeRatesUpdatedAt!)}'
              '${s.exchangeRatesUpdatedBy == null ? '' : ' by ${s.exchangeRatesUpdatedBy}'}.';
    return _Rows([
      _Row(
        'Exchange rates',
        'Giving in other currencies is turned into cedis at these rates when it is saved. '
            'Totals are always in cedis.${changed == null ? '' : '\n\n$changed'}',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in _rates.entries) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: SizedBox(
                      width: 110,
                      child: Text(
                        '1 ${names[e.key]}',
                        style: SelType.body.copyWith(color: Sel.text, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: SelField(
                      controller: e.value,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      errorText: _rateProblem(e.value.text),
                    ),
                  ),
                  const SizedBox(width: SelSpace.x2),
                  Padding(padding: const EdgeInsets.only(top: 14), child: Text('cedis', style: SelType.bodySm)),
                ],
              ),
              const SizedBox(height: SelSpace.x2),
            ],
          ],
        ),
      ),
      if (canRecalculate)
        _Row(
          'Recalculate past giving',
          'After changing a rate, turn every saved dollar, euro and pound entry into cedis again at the new rate. '
              'Church totals move with it, and Pillr says how many entries will change before it does anything.',
          Align(
            alignment: Alignment.centerLeft,
            child: SelButton(label: 'Recalculate past giving…', onPressed: _busy ? null : () => _recalculate(s)),
          ),
        ),
    ]);
  }

  // ------------------------------------------------------------ notifications

  Widget _notificationsTab() {
    final digest = ref.watch(notificationDigestProvider).valueOrNull ?? true;
    final goals = ref.watch(notificationGoalsProvider).valueOrNull ?? true;
    Future<void> set(String key, String id, bool v, FutureProvider<bool> p) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, v);
      ref.invalidate(p);
      if (mounted) setState(() => _savedSwitch = id);
    }

    Widget toggle(String id, bool value, ValueChanged<bool> onChanged) => Row(
      children: [
        Switch(value: value, onChanged: onChanged),
        if (_savedSwitch == id) ...[
          const SizedBox(width: SelSpace.x2),
          const SelTag('Saved', tone: SelTagTone.soft),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Rows([
          _Row(
            'A daily note when entries are waiting',
            'One a day, only on days something waits.',
            toggle('digest', digest, (v) => set(_kPrefDigest, 'digest', v, notificationDigestProvider)),
          ),
          _Row(
            'When an arm reaches a goal',
            'At half way, three quarters and the full target. An arm is something partners give toward, like Tithe or Missions.',
            toggle('goals', goals, (v) => set(_kPrefGoals, 'goals', v, notificationGoalsProvider)),
          ),
        ]),
        const SizedBox(height: SelSpace.x3),
        Text(
          'These go to this browser and to the Pillr app on your phone. Each person chooses their own, and switches save straight away.',
          style: SelType.bodySm,
        ),
      ],
    );
  }

  // ------------------------------------------------------------ account

  Widget _accountTab(UserChurchIndex? idx) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;
    final email = ref.watch(firebaseAuthProvider).currentUser?.email ?? '';
    final church = ref.watch(churchSettingsProvider).valueOrNull?.name ?? 'your church';
    final role = idx == null || idx.role.isEmpty ? '' : idx.role[0].toUpperCase() + idx.role.substring(1);
    return _Rows([
      _Row(
        'You',
        role.isEmpty ? '' : '$role at $church.',
        Row(
          children: [
            SelFace(profile?.fullName ?? email, size: 48),
            const SizedBox(width: SelSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile?.fullName ?? '',
                    style: SelType.bodyMedium.copyWith(color: Sel.ink, fontWeight: FontWeight.w700),
                  ),
                  Text(email, style: SelType.small),
                ],
              ),
            ),
          ],
        ),
      ),
      _Row(
        'Language',
        'Pillr in English or French.',
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: SelSelect<String>(
            value: locale == null ? 'sys' : locale.languageCode,
            onChanged: (v) => ref.read(localeProvider.notifier).setLocale(v == 'sys' || v == null ? null : Locale(v)),
            items: [
              DropdownMenuItem(value: 'sys', child: Text(l10n.settingsLanguageSystem)),
              DropdownMenuItem(value: 'en', child: Text(l10n.settingsLanguageEnglish)),
              DropdownMenuItem(value: 'fr', child: Text(l10n.settingsLanguageFrench)),
            ],
          ),
        ),
      ),
      _Row(
        'Password',
        'We email you a link to choose a new one.',
        Align(
          alignment: Alignment.centerLeft,
          child: SelButton(label: 'Email me a reset link', onPressed: _passwordReset),
        ),
      ),
      _Row(
        'Sign out',
        'On this browser.',
        Align(
          alignment: Alignment.centerLeft,
          child: SelButton(label: 'Sign out', onPressed: () => ref.read(authRepositoryProvider).signOut()),
        ),
      ),
    ]);
  }
}

/// A card of setting rows, split by hairlines.
class _Rows extends StatelessWidget {
  const _Rows(this.rows);

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => SelCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: Sel.rowLine),
          rows[i],
        ],
      ],
    ),
  );
}

/// One setting: what it is and why on the left, the control on the right.
/// Stacked on a narrow screen.
class _Row extends StatelessWidget {
  const _Row(this.title, this.help, this.control);

  final String title;
  final String help;
  final Widget control;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: LayoutBuilder(
      builder: (context, c) {
        final head = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: SelType.bodyMedium.copyWith(color: Sel.ink, fontWeight: FontWeight.w700)),
            ),
            if (help.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(help, style: SelType.bodySm.copyWith(color: const Color(0xFF4D5872))),
            ],
          ],
        );
        if (c.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [head, const SizedBox(height: SelSpace.x3), control],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 4, child: Padding(padding: const EdgeInsets.only(right: SelSpace.x8), child: head)),
            Expanded(flex: 6, child: control),
          ],
        );
      },
    ),
  );
}

/// A light panel holding one preview, with what it shows above.
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.label, required this.child, this.note});

  final String label;
  final Widget child;
  final String? note;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(SelSpace.x4),
    decoration: BoxDecoration(color: Sel.skyTint, borderRadius: BorderRadius.circular(18)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: SelType.small),
        const SizedBox(height: SelSpace.x2),
        child,
        if (note != null) ...[
          const SizedBox(height: SelSpace.x2),
          Text(note!, style: SelType.small.copyWith(color: Sel.text)),
        ],
      ],
    ),
  );
}
