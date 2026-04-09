import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pillr/l10n/app_localizations.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_form_card.dart';
import '../../../common/widgets/pillr_text_field.dart';
import '../../../core/theme/pillr_layout.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/color_utils.dart';
import '../../auth/providers/auth_providers.dart';
import '../../church/providers/church_settings_providers.dart';

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

String _localeDropdownValue(Locale? l) {
  if (l == null) return 'sys';
  return l.languageCode;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  final _colorHex = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _seededChurchId;

  @override
  void dispose() {
    _name.dispose();
    _colorHex.dispose();
    super.dispose();
  }

  Future<void> _saveBranding(String churchId) async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final repo = ref.read(churchSettingsRepositoryProvider);
      final hex = _colorHex.text.trim();
      if (hex.isNotEmpty && parseHexColor(hex) == null) {
        setState(() => _error = 'Use a color like #1A56DB.');
        return;
      }
      await repo.updateBranding(
        churchId: churchId,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        primaryColorHex: hex.isEmpty ? null : hex,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Church settings saved.')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadLogo(String churchId) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (x == null) return;
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final bytes = await x.readAsBytes();
      final path = 'churches/$churchId/branding/logo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final sref = FirebaseStorage.instance.ref(path);
      await sref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await sref.getDownloadURL();
      await ref.read(churchSettingsRepositoryProvider).updateBranding(
            churchId: churchId,
            logoUrl: url,
            logoStoragePath: path,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logo uploaded.')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _passwordResetEmail() async {
    final email = ref.read(firebaseAuthProvider).currentUser?.email;
    if (email == null) return;
    setState(() => _loading = true);
    try {
      await ref.read(firebaseAuthProvider).sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reset link sent to $email')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final settings = ref.watch(churchSettingsProvider).valueOrNull;
    final digest = ref.watch(notificationDigestProvider);
    final goals = ref.watch(notificationGoalsProvider);
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeProvider);

    if (settings != null && _seededChurchId != settings.churchId) {
      _seededChurchId = settings.churchId;
      _name.text = settings.name ?? '';
      _colorHex.text = settings.primaryColorHex ?? '';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: PillrLayout.formMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Settings', style: AppTypography.heading2),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Branding, notifications, and account security.',
                style: AppTypography.body,
              ),
              const SizedBox(height: AppSpacing.xl),
              PillrFormCard(
                title: l10n.settingsLanguage,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('locale-${locale?.languageCode ?? 'sys'}'),
                  initialValue: _localeDropdownValue(locale),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(value: 'sys', child: Text(l10n.settingsLanguageSystem)),
                    DropdownMenuItem(value: 'en', child: Text(l10n.settingsLanguageEnglish)),
                    DropdownMenuItem(value: 'fr', child: Text(l10n.settingsLanguageFrench)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    ref.read(localeProvider.notifier).setLocale(v == 'sys' ? null : Locale(v));
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (idx != null && idx.isAdmin && settings != null) ...[
                PillrFormCard(
                  title: 'Church branding',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PillrTextField(controller: _name, label: 'Church name'),
                      const SizedBox(height: AppSpacing.md),
                      PillrTextField(
                        controller: _colorHex,
                        label: 'Primary color (#RRGGBB)',
                        hint: '#1A56DB',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.sm,
                        children: [
                          PillrButton(
                            label: 'Upload logo',
                            icon: LucideIcons.image,
                            onPressed: _loading ? null : () => _uploadLogo(settings.churchId),
                            variant: PillrButtonVariant.secondary,
                          ),
                          PillrButton(
                            label: 'Save',
                            onPressed: _loading ? null : () => _saveBranding(settings.churchId),
                            variant: PillrButtonVariant.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              PillrFormCard(
                title: 'Notifications',
                subtitle: 'Preferences are stored on this device; server-side digests use Cloud Functions when configured.',
                child: Column(
                  children: [
                    digest.when(
                      loading: () => const SizedBox(height: 8),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (v) => SwitchListTile(
                        title: const Text('Daily pending digest (email/FCM when available)'),
                        value: v,
                        onChanged: (nv) async {
                          final p = await SharedPreferences.getInstance();
                          await p.setBool(_kPrefDigest, nv);
                          ref.invalidate(notificationDigestProvider);
                        },
                      ),
                    ),
                    goals.when(
                      loading: () => const SizedBox(height: 8),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (v) => SwitchListTile(
                        title: const Text('Goal milestone alerts'),
                        value: v,
                        onChanged: (nv) async {
                          final p = await SharedPreferences.getInstance();
                          await p.setBool(_kPrefGoals, nv);
                          ref.invalidate(notificationGoalsProvider);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PillrFormCard(
                title: 'Security',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Password reset email'),
                  subtitle: const Text('Send a link to your signed-in email address.'),
                  trailing: PillrButton(
                    label: 'Send',
                    onPressed: _loading ? null : _passwordResetEmail,
                    variant: PillrButtonVariant.secondary,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: AppTypography.caption.copyWith(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
