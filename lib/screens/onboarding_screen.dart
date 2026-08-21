import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/extensions/async_value_ext.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/date_utils.dart';
import '../design/seline.dart';
import '../core/errors/error_handler.dart';
import '../core/router/church_tenant_gate_cache.dart';
import '../features/arms/providers/arms_providers.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/domain/church_settings.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/periods/providers/periods_providers.dart';

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
    final settings = ref.watch(churchSettingsProvider).valueOrNull;
    _primeFromSettings(settings);

    const titles = [
      'Name your church',
      'Add your first arm',
      'Open a giving period',
      'Invite a teammate',
    ];
    const blurbs = [
      'This is what your team sees when they sign in.',
      'An arm is something partners can give toward.',
      'Entries are recorded against the open period.',
      'Optional — you can do this later from People.',
    ];

    return Scaffold(
      backgroundColor: Sel.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: SelSpace.x6,
              vertical: SelSpace.x12,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Step ${_step + 1} of 4'.toUpperCase(),
                      style: SelType.caption, textAlign: TextAlign.center),
                  const SizedBox(height: SelSpace.x2),
                  Text(titles[_step],
                      style: SelType.title, textAlign: TextAlign.center),
                  const SizedBox(height: SelSpace.x2),
                  Text(blurbs[_step],
                      style: SelType.bodyMuted, textAlign: TextAlign.center),
                  const SizedBox(height: SelSpace.x6),
                  Row(
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        if (i > 0) const SizedBox(width: SelSpace.x2),
                        Expanded(
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: i <= _step ? Sel.soot : Sel.border,
                              borderRadius:
                                  BorderRadius.circular(SelRadius.pill),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: SelSpace.x8),
                  SelCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: SelSpace.x3,
                              vertical: SelSpace.x2 + 2,
                            ),
                            decoration: BoxDecoration(
                              color: Sel.canvas,
                              borderRadius:
                                  BorderRadius.circular(SelRadius.input),
                              border: Border.all(color: Sel.borderMuted),
                            ),
                            child: Text(_error!,
                                style: SelType.bodySm.copyWith(color: Sel.ink)),
                          ),
                          const SizedBox(height: SelSpace.x4),
                        ],
                        ..._stepFields(),
                      ],
                    ),
                  ),
                  const SizedBox(height: SelSpace.x6),
                  Row(
                    children: [
                      if (_step == 3)
                        SelButton(
                          label: 'Skip',
                          kind: SelButtonKind.quiet,
                          onPressed: _loading ? null : _skipInviteAndFinish,
                        ),
                      const Spacer(),
                      SelButton.cyan(
                        label: _step == 3 ? 'Finish setup' : 'Continue',
                        loading: _loading,
                        onPressed: _runStep,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _stepFields() {
    switch (_step) {
      case 0:
        return [
          SelField(controller: _churchName, label: 'Church name'),
          const SizedBox(height: SelSpace.x4),
          SelSelect<String>(
            value: _currencyCode,
            label: 'Currency',
            onChanged: (v) => setState(() {
              _currencyCode = v ?? 'GHS';
              _currencySymbol = _currencies
                  .firstWhere((e) => e.$1 == _currencyCode,
                      orElse: () => _currencies.first)
                  .$2;
            }),
            items: [
              for (final c in _currencies)
                DropdownMenuItem(value: c.$1, child: Text('${c.$1}  ${c.$2}')),
            ],
          ),
          const SizedBox(height: SelSpace.x4),
          SelField(
            controller: _primaryColor,
            label: 'Mark colour',
            hint: 'Optional — #3BA6F1',
          ),
        ];
      case 1:
        return [
          SelField(
            controller: _armName,
            label: 'Arm name',
            hint: 'Missions',
          ),
          const SizedBox(height: SelSpace.x4),
          SelField(
            controller: _armDesc,
            label: 'Description',
            hint: 'Optional',
            maxLines: 2,
          ),
        ];
      case 2:
        return [
          SelField(
            controller: _periodName,
            label: 'Period name',
            hint: 'Q1 2027 Partnership',
          ),
          const SizedBox(height: SelSpace.x4),
          Row(
            children: [
              Expanded(
                child: _DateButton(
                  label: 'Starts',
                  value: _start,
                  onTap: _pickStart,
                ),
              ),
              const SizedBox(width: SelSpace.x3),
              Expanded(
                child: _DateButton(
                  label: 'Ends',
                  value: _end,
                  onTap: _pickEnd,
                ),
              ),
            ],
          ),
        ];
      default:
        return [
          SelField(
            controller: _inviteEmail,
            label: 'Teammate email',
            hint: 'Optional',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: SelSpace.x4),
          SelSelect<String>(
            value: _inviteRole,
            label: 'Role',
            onChanged: (v) => setState(() => _inviteRole = v ?? 'staff'),
            items: const [
              DropdownMenuItem(value: 'pastor', child: Text('Pastor')),
              DropdownMenuItem(value: 'staff', child: Text('Staff')),
              DropdownMenuItem(value: 'admin', child: Text('Admin')),
            ],
          ),
        ];
    }
  }

}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: SelType.bodyMedium),
        const SizedBox(height: SelSpace.x2),
        SelButton(
          label: formatFirestoreDate(value, pattern: 'd MMM y'),
          icon: LucideIcons.calendar,
          expanded: true,
          onPressed: onTap,
        ),
      ],
    );
  }
}
