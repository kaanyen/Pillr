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
  ConsumerState<OnboardingWizardScreen> createState() =>
      _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState
    extends ConsumerState<OnboardingWizardScreen> {
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
    _currencySymbol =
        s.currencySymbol ??
        _currencies
            .firstWhere((e) => e.$1 == c, orElse: () => _currencies.first)
            .$2;
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
          primaryColorHex: _primaryColor.text.trim().isEmpty
              ? null
              : _primaryColor.text.trim(),
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
        await ref
            .read(armsRepositoryProvider)
            .createArm(
              churchId: churchId,
              uid: uid,
              name: _armName.text.trim(),
              description: _armDesc.text.trim().isEmpty
                  ? null
                  : _armDesc.text.trim(),
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
          description: _periodDesc.text.trim().isEmpty
              ? null
              : _periodDesc.text.trim(),
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

  Future<void> _completeOnboarding({
    required String churchId,
    bool sendInvite = true,
  }) async {
    try {
      if (sendInvite && _inviteEmail.text.trim().isNotEmpty) {
        await ref
            .read(inviteRepositoryProvider)
            .sendInvite(
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

    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final church = _churchName.text.trim().isEmpty
        ? 'your church'
        : _churchName.text.trim();

    final steps = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Step ${_step + 1} of 4', style: SelType.bodyMedium),
            const Spacer(),
            Text(
              _step == 3 ? 'Almost done' : 'About ${3 - _step} minutes left',
              style: SelType.bodySm,
            ),
          ],
        ),
        const SizedBox(height: SelSpace.x3),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (_step + 0.5) / 4,
            minHeight: 8,
            backgroundColor: Sel.border,
            valueColor: const AlwaysStoppedAnimation(Sel.sky),
          ),
        ),
        const SizedBox(height: SelSpace.x4),
        for (var i = 0; i < 4; i++)
          _StepRow(
            n: i + 1,
            title: titles[i],
            note: i < _step ? _doneNote(i) : blurbs[i],
            done: i < _step,
            on: i == _step,
            last: i == 3,
          ),
      ],
    );

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titles[_step], style: SelType.title),
        const SizedBox(height: SelSpace.x2),
        Text(blurbs[_step], style: SelType.lead),
        const SizedBox(height: SelSpace.x6),
        SelCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SelSpace.x4,
                    vertical: SelSpace.x3,
                  ),
                  decoration: BoxDecoration(
                    color: Sel.skyTint,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _error!,
                    style: SelType.bodySm.copyWith(color: Sel.ink),
                  ),
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
            SelButton.cyan(
              label: _step == 3 ? 'Finish setup' : 'Continue',
              trailingIcon: LucideIcons.arrowRight,
              loading: _loading,
              onPressed: _runStep,
            ),
            const SizedBox(width: SelSpace.x3),
            if (_step > 0)
              SelButton(
                label: 'Back',
                icon: LucideIcons.arrowLeft,
                kind: SelButtonKind.quiet,
                onPressed: _loading ? null : () => setState(() => _step -= 1),
              ),
            if (_step == 3)
              SelButton(
                label: 'Skip',
                kind: SelButtonKind.quiet,
                onPressed: _loading ? null : _skipInviteAndFinish,
              ),
          ],
        ),
      ],
    );

    final preview = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('How it will look', style: SelType.bodyMedium),
        const SizedBox(height: SelSpace.x3),
        ListenableBuilder(
          listenable: Listenable.merge([_churchName, _armName, _periodName]),
          builder: (context, _) => _SetupPreview(
            church: _churchName.text.trim().isEmpty
                ? 'Your church'
                : _churchName.text.trim(),
            period: _periodName.text.trim().isEmpty
                ? 'Your giving period'
                : _periodName.text.trim(),
            range:
                '${formatFirestoreDate(_start, pattern: 'd MMM y')} to '
                '${formatFirestoreDate(_end, pattern: 'd MMM y')}',
            arm: _armName.text.trim().isEmpty
                ? 'Your first arm'
                : _armName.text.trim(),
            symbol: _currencySymbol,
          ),
        ),
        const SizedBox(height: SelSpace.x3),
        Text(
          'Updates as you type. Nothing is saved until you continue.',
          style: SelType.bodySm,
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Sel.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: SelSpace.x10,
                vertical: SelSpace.x4,
              ),
              decoration: const BoxDecoration(
                color: Sel.card,
                border: Border(bottom: BorderSide(color: Sel.border)),
              ),
              child: Row(
                children: [
                  const PillrMark(size: 32),
                  const SizedBox(width: SelSpace.x3),
                  Text(
                    'pillr',
                    style: SelType.hero.copyWith(
                      fontSize: 24,
                      height: 1,
                      letterSpacing: -1,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      'Setting up $church',
                      style: SelType.bodySm,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? SelSpace.x10 : SelSpace.x4,
                  vertical: SelSpace.x8,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 260, child: steps),
                              const SizedBox(width: SelSpace.x8),
                              Expanded(child: form),
                              const SizedBox(width: SelSpace.x8),
                              SizedBox(width: 340, child: preview),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              steps,
                              const SizedBox(height: SelSpace.x8),
                              form,
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What a finished step shows under its name.
  String _doneNote(int i) => switch (i) {
    0 => _churchName.text.trim(),
    1 => _armName.text.trim(),
    2 => _periodName.text.trim(),
    _ => '',
  };

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
                  .firstWhere(
                    (e) => e.$1 == _currencyCode,
                    orElse: () => _currencies.first,
                  )
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
          SelField(controller: _armName, label: 'Arm name', hint: 'Missions'),
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
                child: _DateButton(label: 'Ends', value: _end, onTap: _pickEnd),
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

/// One step in the setup list: a numbered dot joined to the next by a line.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.n,
    required this.title,
    required this.note,
    required this.done,
    required this.on,
    required this.last,
  });

  final int n;
  final String title;
  final String note;
  final bool done;
  final bool on;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on
                      ? Sel.ink
                      : done
                      ? Sel.skyWash
                      : Sel.track,
                  boxShadow: on
                      ? const [
                          BoxShadow(color: Color(0xFFDCECFB), spreadRadius: 5),
                        ]
                      : null,
                ),
                child: done
                    ? const Icon(LucideIcons.check, size: 16, color: Sel.ink)
                    : Text(
                        '$n',
                        style: SelType.tag.copyWith(
                          color: on ? Sel.card : Sel.warm,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: done ? const Color(0xFF9ACFF6) : Sel.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: SelSpace.x3),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: SelSpace.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SelType.bodyMedium.copyWith(
                      color: on || done ? Sel.ink : Sel.text,
                    ),
                  ),
                  if (note.isNotEmpty) Text(note, style: SelType.bodySm),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small Overview header as it will look once setup is done.
class _SetupPreview extends StatelessWidget {
  const _SetupPreview({
    required this.church,
    required this.period,
    required this.range,
    required this.arm,
    required this.symbol,
  });

  final String church;
  final String period;
  final String range;
  final String arm;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().month;
    return SelCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: SelSpace.x4,
              vertical: SelSpace.x3,
            ),
            decoration: const BoxDecoration(
              color: Sel.rail,
              border: Border(bottom: BorderSide(color: Sel.railEdge)),
            ),
            child: Row(
              children: [
                const PillrMark(size: 20),
                const SizedBox(width: SelSpace.x2),
                Expanded(
                  child: Text(
                    church,
                    style: SelType.bodySm.copyWith(
                      color: Sel.ink,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Overview', style: SelType.subtitle),
                Text('$period · $range', style: SelType.bodySm),
                const SizedBox(height: SelSpace.x4),
                Row(
                  children: [
                    for (var m = 1; m <= 12; m++) ...[
                      if (m > 1) const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 28,
                          decoration: BoxDecoration(
                            color: m == now ? Sel.sky : const Color(0xFFDCECFB),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: SelSpace.x3),
                Row(
                  children: [
                    Text(arm, style: SelType.bodySm),
                    const Spacer(),
                    Text('${symbol}0.00', style: SelType.bodyMedium),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
