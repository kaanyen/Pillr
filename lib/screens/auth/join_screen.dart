import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/errors/error_handler.dart';
import '../../core/router/church_tenant_gate_cache.dart';
import '../../core/router/user_church_index_cache.dart';
import '../../core/utils/validation_utils.dart';
import '../../design/seline.dart';
import '../../features/auth/domain/invite_models.dart';
import '../../features/auth/providers/auth_providers.dart';
import 'auth_shell.dart';

/// Join with an invite code. Two steps: verify the code, then set up the
/// account. The step indicator is a hairline pair of bars rather than numbered
/// circles — this is a two-step form, not a wizard.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, this.prefilledCode});

  /// Code lifted from the invite email link (`?code=…`).
  final String? prefilledCode;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();

  int _step = 1;
  bool _busy = false;
  String? _error;
  InviteValidationResult? _validated;

  @override
  void initState() {
    super.initState();
    if (widget.prefilledCode != null && widget.prefilledCode!.isNotEmpty) {
      _code.text = widget.prefilledCode!.toUpperCase();
    }
  }

  @override
  void dispose() {
    for (final c in [_email, _code, _name, _phone, _password, _password2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() => _error = null);
    if (!isValidEmail(_email.text)) {
      setState(() => _error = 'Enter a valid email.');
      return;
    }
    if (_code.text.trim().length < 6) {
      setState(() => _error = 'Enter your invite code.');
      return;
    }
    setState(() => _busy = true);
    final res = await ref
        .read(authRepositoryProvider)
        .validateInvite(email: _email.text, code: _code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!res.valid) {
        _error = res.errorMessage ?? 'Invitation could not be verified.';
        return;
      }
      _validated = res;
      _step = 2;
    });
  }

  Future<void> _createAccount() async {
    setState(() => _error = null);
    final pwdErr = passwordErrorMessage(_password.text);
    if (pwdErr != null) {
      setState(() => _error = pwdErr);
      return;
    }
    if (_password.text != _password2.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Full name is required.');
      return;
    }
    if (_validated?.codeId == null || _validated?.churchId == null) {
      setState(() => _error = 'Session expired. Go back and verify your invite again.');
      return;
    }

    setState(() => _busy = true);
    final auth = ref.read(authRepositoryProvider);
    try {
      await auth.createAuthUser(email: _email.text, password: _password.text);
      try {
        await auth.completeRegistration(
          fullName: _name.text,
          phone: _phone.text,
          codeId: _validated!.codeId!,
          churchId: _validated!.churchId!,
        );
      } catch (_) {
        // Roll the auth user back so a failed registration cannot strand
        // someone with an account that belongs to no church.
        await auth.deleteCurrentUser();
        rethrow;
      }
      if (mounted) {
        UserChurchIndexCache.clear();
        ChurchTenantGateCache.clear();
        context.go('/overview');
      }
    } catch (e) {
      if (mounted) setState(() => _error = humanizeAuthException(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final church = _validated?.churchName;

    return AuthShell(
      width: 440,
      title: _step == 1 ? 'Join your ' : 'Set up your ',
      highlight: _step == 1 ? 'church' : 'account',
      subtitle: _step == 1
          ? 'Enter the email your invite was sent to, and the code from it.'
          : church == null
              ? 'Choose how you will sign in from now on.'
              : 'You are joining $church.',
      footer: GestureDetector(
        onTap: () => _step == 2
            ? setState(() {
                _step = 1;
                _error = null;
              })
            : context.go('/'),
        child: Text(
          _step == 2 ? 'Back to the code step' : 'Back',
          style: SelType.small.copyWith(
            color: Sel.cyanEdge,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepBars(step: _step),
          const SizedBox(height: SelSpace.x6),
          if (_error != null) AuthNotice(message: _error!),
          if (_step == 1) ..._stepOne() else ..._stepTwo(),
        ],
      ),
    );
  }

  List<Widget> _stepOne() => [
        SelField(
          controller: _email,
          label: 'Email',
          hint: 'you@church.org',
          keyboardType: TextInputType.emailAddress,
          prefixIcon: LucideIcons.mail,
        ),
        const SizedBox(height: SelSpace.x4),
        SelField(
          controller: _code,
          label: 'Invite code',
          hint: 'ABCD1234',
          textCapitalization: TextCapitalization.characters,
          prefixIcon: LucideIcons.keyRound,
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: SelSpace.x6),
        SelButton.cyan(
          label: 'Verify code',
          expanded: true,
          loading: _busy,
          onPressed: _verify,
        ),
      ];

  List<Widget> _stepTwo() => [
        SelField(controller: _name, label: 'Full name', hint: 'Ama Boateng'),
        const SizedBox(height: SelSpace.x4),
        SelField(
          controller: _phone,
          label: 'Phone',
          hint: 'Optional',
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: SelSpace.x4),
        SelField(
          controller: _password,
          label: 'Password',
          hint: 'At least 8 characters',
          obscureText: true,
        ),
        const SizedBox(height: SelSpace.x4),
        SelField(
          controller: _password2,
          label: 'Confirm password',
          obscureText: true,
          onSubmitted: (_) => _createAccount(),
        ),
        const SizedBox(height: SelSpace.x6),
        SelButton.cyan(
          label: 'Create account',
          expanded: true,
          loading: _busy,
          onPressed: _createAccount,
        ),
      ];
}

/// Two hairline bars. The filled one is Soot, not cyan — progress is not an
/// action, and the cyan belongs to the button beneath.
class _StepBars extends StatelessWidget {
  const _StepBars({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 2; i++) ...[
          if (i > 1) const SizedBox(width: SelSpace.x2),
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: i <= step ? Sel.soot : Sel.border,
                borderRadius: BorderRadius.circular(SelRadius.pill),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
