import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/providers/locale_provider.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/church/presentation/exchange_rates_settings_panel.dart';
import '../features/church/presentation/monthly_partner_email_panel.dart';

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

/// Settings — stacked panels, one concern each.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  final _colorHex = TextEditingController();
  bool _busy = false;
  bool _seeded = false;
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    _colorHex.dispose();
    super.dispose();
  }

  Future<void> _saveBranding(String churchId) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await ref.read(churchSettingsRepositoryProvider).updateBranding(
            churchId: churchId,
            name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            primaryColorHex:
                _colorHex.text.trim().isEmpty ? null : _colorHex.text.trim(),
          );
      if (mounted) setState(() => _notice = 'Church settings saved.');
    } catch (e) {
      if (mounted) setState(() => _notice = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadLogo(String churchId) async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      imageQuality: 85,
    );
    if (x == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await x.readAsBytes();
      final path = 'churches/$churchId/branding/logo.jpg';
      final sref = FirebaseStorage.instance.ref(path);
      await sref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await sref.getDownloadURL();
      await ref.read(churchSettingsRepositoryProvider).updateBranding(
            churchId: churchId,
            logoUrl: url,
            logoStoragePath: path,
          );
      if (mounted) setState(() => _notice = 'Logo uploaded.');
    } catch (e) {
      if (mounted) setState(() => _notice = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _passwordReset() async {
    final email = ref.read(firebaseAuthProvider).currentUser?.email;
    if (email == null) return;
    try {
      await ref.read(firebaseAuthProvider).sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _notice = 'Reset link sent to $email.');
    } catch (e) {
      if (mounted) setState(() => _notice = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final settings = ref.watch(churchSettingsProvider).valueOrNull;
    final locale = ref.watch(localeProvider);
    final digest = ref.watch(notificationDigestProvider);
    final goals = ref.watch(notificationGoalsProvider);
    final canBrand = idx?.isAdmin ?? false;
    final canPartnerEmail = idx != null && (idx.isPastor || idx.isAdmin);
    final canRates = idx?.canEditExchangeRates ?? false;

    if (settings != null && !_seeded) {
      _seeded = true;
      _name.text = settings.name ?? '';
      _colorHex.text = settings.primaryColorHex ?? '';
    }

    final email = ref.watch(firebaseAuthProvider).currentUser?.email ?? '';
    final churchName = settings?.name ?? '';
    final dirty = settings != null &&
        (_name.text.trim() != (settings.name ?? '') ||
            _colorHex.text.trim() != (settings.primaryColorHex ?? ''));
    Color? parse(String hex) {
      final h = hex.replaceAll('#', '').trim();
      if (h.length != 6) return null;
      final v = int.tryParse(h, radix: 16);
      return v == null ? null : Color(0xFF000000 | v);
    }

    final markColour = parse(_colorHex.text) ?? Sel.ink;
    const swatches = ['#13426F', '#1F6F4A', '#7A2440', '#B4532A', '#333333'];
    final initials = churchName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    Widget section(String title, String help, Widget body, {bool first = false}) =>
        Container(
          decoration: BoxDecoration(
            border: first
                ? null
                : const Border(top: BorderSide(color: Sel.border)),
          ),
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 26),
          child: LayoutBuilder(
            builder: (context, c) {
              final head = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SelType.subtitle),
                  const SizedBox(height: SelSpace.x1),
                  Text(help, style: SelType.small),
                ],
              );
              if (c.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [head, const SizedBox(height: SelSpace.x4), body],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: c.maxWidth * 0.36, child: head),
                  const SizedBox(width: SelSpace.x8),
                  Expanded(child: body),
                ],
              );
            },
          ),
        );

    final sections = <Widget>[
      if (canBrand && settings != null)
        section(
          'Church',
          'Shown in the sidebar, on emails to partners and on exports.',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelField(
                controller: _name,
                label: 'Church name',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: SelSpace.x4),
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: markColour,
                      shape: BoxShape.circle,
                      image: settings.logoUrl == null
                          ? null
                          : DecorationImage(
                              image: NetworkImage(settings.logoUrl!),
                              fit: BoxFit.cover,
                            ),
                    ),
                    child: settings.logoUrl == null
                        ? Text(
                            initials,
                            style: SelType.subtitle.copyWith(color: Sel.card),
                          )
                        : null,
                  ),
                  const SizedBox(width: SelSpace.x4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Logo', style: SelType.bodyMedium),
                        Text(
                          'Square image, up to 1 MB. Until you add one, Pillr uses your initials.',
                          style: SelType.small,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: SelSpace.x3),
                  SelButton(
                    label: 'Upload logo',
                    onPressed: _busy
                        ? null
                        : () => _uploadLogo(settings.churchId),
                  ),
                ],
              ),
              const SizedBox(height: SelSpace.x4),
              Text('Mark colour', style: SelType.bodyMedium),
              const SizedBox(height: SelSpace.x2),
              Wrap(
                spacing: SelSpace.x3,
                runSpacing: SelSpace.x2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final hex in swatches)
                    GestureDetector(
                      onTap: () => setState(() => _colorHex.text = hex),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Container(
                          width: 40,
                          height: 40,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _colorHex.text.toUpperCase() == hex
                                  ? Sel.ink
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: parse(hex),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Text(
                    "Only the church's initials or logo takes this colour. Pillr itself stays blue.",
                    style: SelType.small,
                  ),
                ],
              ),
            ],
          ),
          first: true,
        ),
      section(
        'Telling you',
        'For you only, on this device. Each person chooses their own.',
        Column(
          children: [
            _Toggle(
              label: 'Daily summary when entries are waiting',
              help: 'One summary a day, only on days something is waiting.',
              value: digest.valueOrNull ?? true,
              onChanged: (v) async {
                final p = await SharedPreferences.getInstance();
                await p.setBool(_kPrefDigest, v);
                ref.invalidate(notificationDigestProvider);
              },
            ),
            const Divider(height: 1, color: Sel.rowLine),
            _Toggle(
              label: 'Goal milestones',
              help: 'When an arm passes 50%, 75% or 100% of its target.',
              value: goals.valueOrNull ?? true,
              onChanged: (v) async {
                final p = await SharedPreferences.getInstance();
                await p.setBool(_kPrefGoals, v);
                ref.invalidate(notificationGoalsProvider);
              },
            ),
          ],
        ),
        first: !(canBrand && settings != null),
      ),
      if (canPartnerEmail && settings != null)
        section(
          'Thanking partners',
          'A monthly email to every partner with an email address, listing their approved giving.',
          MonthlyPartnerEmailPanel(idx: idx, settings: settings, bare: true),
        ),
      if (canRates && settings != null)
        section(
          'Exchange rates',
          'Base currency is Ghana cedi. Rates convert foreign giving when entries are saved.',
          ExchangeRatesSettingsPanel(
            churchId: settings.churchId,
            initialRates: settings.exchangeRates,
            bare: true,
          ),
        ),
      section(
        'You',
        email,
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: SelSelect<String>(
                label: 'Language',
                value: locale == null ? 'sys' : locale.languageCode,
                onChanged: (v) => ref
                    .read(localeProvider.notifier)
                    .setLocale(v == 'sys' || v == null ? null : Locale(v)),
                items: [
                  DropdownMenuItem(
                    value: 'sys',
                    child: Text(l10n.settingsLanguageSystem),
                  ),
                  DropdownMenuItem(
                    value: 'en',
                    child: Text(l10n.settingsLanguageEnglish),
                  ),
                  DropdownMenuItem(
                    value: 'fr',
                    child: Text(l10n.settingsLanguageFrench),
                  ),
                ],
              ),
            ),
            const SizedBox(width: SelSpace.x3),
            SelButton(
              label: 'Email me a password reset link',
              onPressed: _passwordReset,
            ),
          ],
        ),
      ),
    ];

    return SelPageBody(
      children: [
        SelPageTitle(
          title: 'Settings',
          subtitle: churchName.isEmpty
              ? 'How your church appears, and what Pillr tells you'
              : 'How $churchName appears, and what Pillr tells you',
        ),
        if (_notice != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: SelSpace.x4,
              vertical: SelSpace.x3,
            ),
            decoration: BoxDecoration(
              color: Sel.skyTint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(_notice!, style: SelType.bodySm.copyWith(color: Sel.ink)),
          ),
          const SizedBox(height: SelSpace.x4),
        ],
        SelCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: sections,
          ),
        ),
        if (dirty) ...[
          const SizedBox(height: SelSpace.x4),
          Container(
            padding: const EdgeInsets.fromLTRB(26, 10, 10, 10),
            decoration: BoxDecoration(
              color: Sel.ink,
              borderRadius: BorderRadius.circular(SelRadius.pill),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'You changed the church details',
                      style: SelType.body.copyWith(
                        color: Sel.card,
                        fontWeight: FontWeight.w700,
                      ),
                      children: [
                        TextSpan(
                          text: ' · not saved yet',
                          style: SelType.body.copyWith(
                            color: const Color(0xFFC9DEF3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _name.text = settings.name ?? '';
                    _colorHex.text = settings.primaryColorHex ?? '';
                  }),
                  child: Text(
                    'Discard',
                    style: SelType.button.copyWith(color: Sel.card),
                  ),
                ),
                const SizedBox(width: SelSpace.x2),
                Material(
                  color: Sel.card,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: _busy
                        ? null
                        : () => _saveBranding(settings.churchId),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 13,
                      ),
                      child: Text(
                        'Save changes',
                        style: SelType.button.copyWith(color: Sel.ink),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.help,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String help;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SelSpace.x3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: SelType.bodyMedium),
                Text(help, style: SelType.small),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
