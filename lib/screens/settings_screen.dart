import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/providers/locale_provider.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';

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

    if (settings != null && !_seeded) {
      _seeded = true;
      _name.text = settings.name ?? '';
      _colorHex.text = settings.primaryColorHex ?? '';
    }

    return SelPageBody(
      maxWidth: 720,
      children: [
        const SelPageTitle(
          title: 'Settings',
          subtitle: 'Your preferences, and how this workspace looks.',
        ),

        if (_notice != null) ...[
          SelCard(
            lift: SelLift.flat,
            padding: const EdgeInsets.symmetric(
              horizontal: SelSpace.x4,
              vertical: SelSpace.x3,
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.info, size: 14, color: Sel.ash),
                const SizedBox(width: SelSpace.x2),
                Expanded(child: Text(_notice!, style: SelType.bodySm)),
              ],
            ),
          ),
          const SizedBox(height: SelSpace.x4),
        ],

        SelPanel(
          title: 'Language',
          subtitle: 'Applies to this device.',
          child: SelSelect<String>(
            value: locale == null ? 'sys' : locale.languageCode,
            onChanged: (v) => ref
                .read(localeProvider.notifier)
                .setLocale(v == 'sys' || v == null ? null : Locale(v)),
            items: [
              DropdownMenuItem(value: 'sys', child: Text(l10n.settingsLanguageSystem)),
              DropdownMenuItem(value: 'en', child: Text(l10n.settingsLanguageEnglish)),
              DropdownMenuItem(value: 'fr', child: Text(l10n.settingsLanguageFrench)),
            ],
          ),
        ),

        const SizedBox(height: SelSpace.x4),

        if (canBrand && settings != null) ...[
          SelPanel(
            title: 'Church branding',
            subtitle:
                'Your colour appears on the church mark only — the rest of '
                'Pillr stays neutral by design.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelField(controller: _name, label: 'Church name'),
                const SizedBox(height: SelSpace.x4),
                SelField(
                  controller: _colorHex,
                  label: 'Mark colour',
                  hint: '#3BA6F1',
                ),
                const SizedBox(height: SelSpace.x6),
                Row(
                  children: [
                    SelButton(
                      label: 'Upload logo',
                      icon: LucideIcons.image,
                      onPressed: _busy ? null : () => _uploadLogo(settings.churchId),
                    ),
                    const SizedBox(width: SelSpace.x2),
                    SelButton.cyan(
                      label: 'Save',
                      loading: _busy,
                      onPressed: () => _saveBranding(settings.churchId),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: SelSpace.x4),
        ],

        SelPanel(
          title: 'Notifications',
          subtitle: 'Stored on this device.',
          contentPadding: EdgeInsets.zero,
          child: Column(
            children: [
              _Toggle(
                label: 'Daily pending digest',
                help: 'One summary a day when entries are waiting.',
                value: digest.valueOrNull ?? true,
                onChanged: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setBool(_kPrefDigest, v);
                  ref.invalidate(notificationDigestProvider);
                },
              ),
              const Divider(height: 1, color: Sel.border),
              _Toggle(
                label: 'Goal milestone alerts',
                help: 'When a goal crosses 50%, 75% or 100%.',
                value: goals.valueOrNull ?? true,
                onChanged: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setBool(_kPrefGoals, v);
                  ref.invalidate(notificationGoalsProvider);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: SelSpace.x4),

        SelPanel(
          title: 'Security',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Send a password reset link to your signed-in address.',
                  style: SelType.bodyMuted,
                ),
              ),
              const SizedBox(width: SelSpace.x4),
              SelButton(label: 'Send link', onPressed: _passwordReset),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: SelSpace.cardPad,
        vertical: SelSpace.x3,
      ),
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
