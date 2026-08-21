import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/router/church_tenant_gate_cache.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../common/widgets/pillr_form_card.dart';
import '../../../common/widgets/pillr_text_field.dart';
import '../../arms/providers/arms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../church/domain/church_settings.dart';
import '../../church/providers/church_settings_providers.dart';
import '../../periods/providers/periods_providers.dart';

class OnboardingWizardScreen extends ConsumerStatefulWidget {
  const OnboardingWizardScreen({super.key});

  @override
  ConsumerState<OnboardingWizardScreen> createState() => _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState extends ConsumerState<OnboardingWizardScreen> {
  int _step = 0;
  bool _loading = false;
  String? _error;
  bool _primedFields = false;

  final _churchName = TextEditingController();
  final _primaryColor = TextEditingController();
  String _currencyCode = 'GHS';
  String _currencySymbol = '\u20B5';

  final _armName = TextEditingController();
  final _armDesc = TextEditingController();

  final _periodName = TextEditingController();
  final _periodDesc = TextEditingController();
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 365));

  final _inviteEmail = TextEditingController();
  String _inviteRole = 'staff';

  static const _currencies = [
    ('GHS', '\u20B5'),
    ('USD', r'$'),
    ('EUR', '\u20AC'),
    ('GBP', '\u00A3'),
  ];

  @override
  void dispose() {
    _churchName.dispose();
    _primaryColor.dispose();
    _armName.dispose();
    _armDesc.dispose();
    _periodName.dispose();
    _periodDesc.dispose();
    _inviteEmail.dispose();
    super.dispose();
  }

  void _primeFromSettings(ChurchSettings? s) {
    if (_primedFields || s == null) return;
    _primedFields = true;
    _churchName.text = s.name ?? '';
    if (s.primaryColorHex != null && s.primaryColorHex!.isNotEmpty) {
      _primaryColor.text = s.primaryColorHex!;
    }
    final c = (s.currency ?? 'GHS').toUpperCase();
    _currencyCode = c;
    _currencySymbol = s.currencySymbol ?? _currencies.firstWhere((e) => e.$1 == c, orElse: () => _currencies.first).$2;
  }

  Future<void> _runStep() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (idx == null || uid == null) {
      setState(() => _loading = false);
      return;
    }
    final churchId = idx.churchId;

    try {
      if (_step == 0) {
        if (_churchName.text.trim().isEmpty) {
          throw AppException('Church name is required.');
        }
        final repo = ref.read(churchSettingsRepositoryProvider);
        await repo.updateBranding(
          churchId: churchId,
          name: _churchName.text.trim(),
          primaryColorHex: _primaryColor.text.trim().isEmpty ? null : _primaryColor.text.trim(),
        );
        await repo.updateLocaleCurrency(
          churchId: churchId,
          currency: _currencyCode,
          currencySymbol: _currencySymbol,
        );
      } else if (_step == 1) {
        if (_armName.text.trim().isEmpty) {
          throw AppException('Arm name is required.');
        }
        await ref.read(armsRepositoryProvider).createArm(
              churchId: churchId,
              uid: uid,
              name: _armName.text.trim(),
              description: _armDesc.text.trim().isEmpty ? null : _armDesc.text.trim(),
            );
      } else if (_step == 2) {
        if (_periodName.text.trim().isEmpty) {
          throw AppException('Period name is required.');
        }
        if (!_end.isAfter(_start)) {
          throw AppException('End date must be after start date.');
        }
        final periods = ref.read(periodsRepositoryProvider);
        final periodId = await periods.createPeriod(
          churchId: churchId,
          uid: uid,
          name: _periodName.text.trim(),
          description: _periodDesc.text.trim().isEmpty ? null : _periodDesc.text.trim(),
          startDate: _start,
          endDate: _end,
          isActive: false,
        );
        await periods.activatePeriod(churchId: churchId, periodId: periodId);
      } else if (_step == 3) {
        await _completeOnboarding(churchId: churchId);
        return;
      }
      if (mounted) {
        setState(() {
          _step += 1;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = humanizeAuthException(e);
        });
      }
    }
  }

  Future<void> _completeOnboarding({required String churchId, bool sendInvite = true}) async {
    try {
      if (sendInvite && _inviteEmail.text.trim().isNotEmpty) {
        await ref.read(inviteRepositoryProvider).sendInvite(
              churchId: churchId,
              email: _inviteEmail.text,
              role: _inviteRole,
            );
      }
      await ref.read(churchSettingsRepositoryProvider).completeSetup(churchId);
      ChurchTenantGateCache.clear();
      ref.invalidate(churchSettingsProvider);
      if (mounted) context.go('/overview');
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = humanizeAuthException(e);
        });
      }
    }
  }

  Future<void> _skipInviteAndFinish() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    final idx = ref.read(userChurchIndexProvider).valueOrNull;
    if (idx == null) {
      setState(() => _loading = false);
      return;
    }
    await _completeOnboarding(churchId: idx.churchId, sendInvite: false);
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _start = d);
  }

  Future<void> _pickEnd() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _end,
      firstDate: _start,
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _end = d);
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final settings = ref.watch(churchSettingsProvider).valueOrNull;
    _primeFromSettings(settings);

    if (idx == null || !(idx.isAdmin || idx.isPastor)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/overview');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final stepLabel = '${_step + 1} of 4';

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text('Set up your church · $stepLabel'),
        automaticallyImplyLeading: false,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: PillrFormCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_step == 0) ...[
                    Text('Church basics', style: AppTypography.heading),
                    const SizedBox(height: AppSpacing.md),
                    PillrTextField(controller: _churchName, label: 'Church name'),
                    const SizedBox(height: AppSpacing.md),
                    PillrTextField(
                      controller: _primaryColor,
                      label: 'Primary color (hex, optional)',
                      hint: '#1A56DB',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: _currencyCode,
                      decoration: const InputDecoration(labelText: 'Currency'),
                      items: [
                        for (final c in _currencies)
                          DropdownMenuItem(value: c.$1, child: Text(c.$1)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _currencyCode = v;
                          _currencySymbol = _currencies.firstWhere((e) => e.$1 == v).$2;
                        });
                      },
                    ),
                  ],
                  if (_step == 1) ...[
                    Text('First partnership arm', style: AppTypography.heading),
                    const SizedBox(height: AppSpacing.md),
                    PillrTextField(controller: _armName, label: 'Arm name'),
                    const SizedBox(height: AppSpacing.md),
                    PillrTextField(controller: _armDesc, label: 'Description (optional)'),
                  ],
                  if (_step == 2) ...[
                    Text('Active giving period', style: AppTypography.heading),
                    const SizedBox(height: AppSpacing.md),
                    PillrTextField(controller: _periodName, label: 'Period name'),
                    const SizedBox(height: AppSpacing.md),
                    PillrTextField(controller: _periodDesc, label: 'Description (optional)'),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickStart,
                            icon: const Icon(LucideIcons.calendar, size: 18),
                            label: Text('Start: ${_start.toLocal().toString().split(' ').first}'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickEnd,
                            icon: const Icon(LucideIcons.calendar, size: 18),
                            label: Text('End: ${_end.toLocal().toString().split(' ').first}'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_step == 3) ...[
                    Text('Invite a teammate (optional)', style: AppTypography.heading),
                    const SizedBox(height: AppSpacing.md),
                    PillrTextField(
                      controller: _inviteEmail,
                      label: 'Email',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: _inviteRole,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: const [
                        DropdownMenuItem(value: 'staff', child: Text('Staff')),
                        DropdownMenuItem(value: 'pastor', child: Text('Pastor')),
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      ],
                      onChanged: (v) => setState(() => _inviteRole = v ?? 'staff'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton(
                      onPressed: _loading ? null : _skipInviteAndFinish,
                      child: const Text('Skip'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(_error!, style: AppTypography.body.copyWith(color: AppColors.ink)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: _loading ? null : _runStep,
                    child: _loading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_step == 3 ? 'Finish' : 'Next'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
