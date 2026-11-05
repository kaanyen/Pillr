import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/errors/error_handler.dart';
import '../../core/extensions/async_value_ext.dart';
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
  /// True when there is a signed-in account that has no church yet.
  ///
  /// The router forces this account to /join and refuses every other route,
  /// so navigating away is not an option — the only real exit is to sign out.
  bool get _signedIn => ref.watch(authStateProvider).valueOrNull != null;

  /// Leaves the screen for good.
  ///
  /// Plain navigation cannot escape: the redirect sees an account with no
  /// church membership and sends it straight back here, which is why Back
  /// appeared to do nothing. Signing out first clears that condition.
  Future<void> _leave() async {
    if (_signedIn) {
      await ref.read(authRepositoryProvider).signOut();
      UserChurchIndexCache.clear();
      ChurchTenantGateCache.clear();
    }
    if (mounted) context.go('/');
  }

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
      setState(
        () => _error = 'Session expired. Go back and verify your invite again.',
      );
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
    final role = _validated?.role ?? 'staff';

    return AuthShell(
      width: 480,
      title: _step == 1 ? 'Join your church' : 'Set up your account',
      subtitle: _step == 1
          ? 'Enter the email your invite was sent to, and the code from it.'
          : "This is how you'll sign in from now on.",
      panel: _step == 2 && church != null
          ? _InvitePanel(church: church, role: role)
          : const _JoinBrandPanel(),
      topLink: SelLink(
        label: _signedIn ? 'Sign out' : 'I already have an account',
        onTap: _leave,
      ),
      footer: _step == 2
          ? SelLink(
              label: 'Back to the code step',
              onTap: () => setState(() {
                _step = 1;
                _error = null;
              }),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Steps(step: _step),
          const SizedBox(height: SelSpace.x6),
          if (_error != null) AuthNotice(message: _error!),
          if (_step == 1) ..._stepOne() else ..._stepTwo(church),
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
      label: 'Check my code',
      trailingIcon: LucideIcons.arrowRight,
      expanded: true,
      loading: _busy,
      onPressed: _verify,
    ),
  ];

  List<Widget> _stepTwo(String? church) => [
    SelField(
      controller: _name,
      label: 'Full name',
      hint: 'Ama Boateng',
      prefixIcon: LucideIcons.user,
    ),
    const SizedBox(height: SelSpace.x4),
    _FieldLabel('Email', note: 'From your invite'),
    const SizedBox(height: SelSpace.x2),
    SelField(
      controller: _email,
      readOnly: true,
      enabled: false,
      prefixIcon: LucideIcons.mail,
      suffixIcon: const Padding(
        padding: EdgeInsets.only(right: SelSpace.x4),
        child: Icon(LucideIcons.lock, size: 16, color: Sel.warm),
      ),
    ),
    const SizedBox(height: SelSpace.x4),
    _FieldLabel('Phone', note: 'Optional'),
    const SizedBox(height: SelSpace.x2),
    SelField(
      controller: _phone,
      hint: '024 318 7702',
      keyboardType: TextInputType.phone,
      prefixIcon: LucideIcons.smartphone,
    ),
    const SizedBox(height: SelSpace.x4),
    SelField(
      controller: _password,
      label: 'Password',
      hint: 'At least 8 characters',
      obscureText: true,
      prefixIcon: LucideIcons.lock,
      onChanged: (_) => setState(() {}),
    ),
    const SizedBox(height: SelSpace.x2),
    _Strength(password: _password.text),
    const SizedBox(height: SelSpace.x4),
    SelField(
      controller: _password2,
      label: 'Type it again',
      obscureText: true,
      prefixIcon: LucideIcons.lock,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _createAccount(),
    ),
    if (_password2.text.isNotEmpty) ...[
      const SizedBox(height: SelSpace.x2),
      _Rule(
        ok: _password2.text == _password.text,
        label: _password2.text == _password.text
            ? 'They match'
            : "They don't match yet",
      ),
    ],
    const SizedBox(height: SelSpace.x6),
    SelButton.cyan(
      label: church == null ? 'Create account' : 'Join $church',
      trailingIcon: LucideIcons.arrowRight,
      expanded: true,
      loading: _busy,
      onPressed: _createAccount,
    ),
  ];
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {this.note});

  final String label;
  final String? note;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(label, style: SelType.bodyMedium),
      const Spacer(),
      if (note != null) Text(note!, style: SelType.bodySm),
    ],
  );
}

/// Code ✓ — Your account — Done.
class _Steps extends StatelessWidget {
  const _Steps({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    Widget dot(int n, String label) {
      final done = n < step;
      final on = n == step;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on
                  ? Sel.ink
                  : done
                  ? Sel.skyWash
                  : Sel.track,
            ),
            child: done
                ? const Icon(LucideIcons.check, size: 14, color: Sel.ink)
                : Text(
                    '$n',
                    style: SelType.tag.copyWith(
                      color: on ? Sel.card : Sel.warm,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          const SizedBox(width: SelSpace.x2),
          Text(
            label,
            style: SelType.bodySm.copyWith(
              color: on ? Sel.ink : Sel.warm,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    Widget bar(bool full) => Container(
      width: 28,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: SelSpace.x2),
      decoration: BoxDecoration(
        color: full ? Sel.sky : Sel.border,
        borderRadius: BorderRadius.circular(2),
      ),
    );

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: SelSpace.x2,
      children: [
        dot(1, 'Code'),
        bar(step > 1),
        dot(2, 'Your account'),
        bar(false),
        dot(3, 'Done'),
      ],
    );
  }
}

/// Four bars and the rules they stand for.
class _Strength extends StatelessWidget {
  const _Strength({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final long = password.length >= 8;
    final number = password.contains(RegExp(r'\d'));
    final symbol = password.contains(RegExp(r'[^A-Za-z0-9]'));
    final mixed =
        password.contains(RegExp(r'[a-z]')) &&
        password.contains(RegExp(r'[A-Z]'));
    final score = [long, number, symbol, mixed].where((b) => b).length;
    final word = switch (score) {
      0 || 1 => 'Weak',
      2 => 'Fair',
      3 => 'Good',
      _ => 'Strong',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: i < score && password.isNotEmpty
                        ? Sel.sky
                        : Sel.border,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: SelSpace.x2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: SelSpace.x4,
                runSpacing: 4,
                children: [
                  _Rule(ok: long, label: '8 or more characters'),
                  _Rule(ok: number, label: 'A number'),
                  _Rule(ok: symbol, label: 'A symbol, for extra strength'),
                ],
              ),
            ),
            if (password.isNotEmpty)
              Text(
                word,
                style: SelType.bodySm.copyWith(
                  color: Sel.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = ok ? Sel.success : Sel.warm;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ok ? LucideIcons.check : LucideIcons.x, size: 14, color: c),
        const SizedBox(width: 6),
        Text(label, style: SelType.bodySm.copyWith(color: c)),
      ],
    );
  }
}

class _JoinBrandPanel extends StatelessWidget {
  const _JoinBrandPanel();

  @override
  Widget build(BuildContext context) {
    final compact = AuthPanelScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthPanelLogo(),
        SizedBox(height: compact ? SelSpace.x4 : SelSpace.x10),
        const AuthPanelHeadline(
          title: 'Your church is waiting for you.',
          body:
              'Use the code from your invite email. It tells Pillr which '
              "church you're joining and what you can do there.",
        ),
        if (!compact) ...[
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: SelSpace.x6),
                child: AspectRatio(
                  aspectRatio: 440 / 340,
                  child: CustomPaint(painter: ChurchFrontPainter()),
                ),
              ),
            ),
          ),
          const AuthPanelFoot(),
        ],
      ],
    );
  }
}

/// The invitation as a ticket: the church, the role, and what that role can
/// and can't do.
class _InvitePanel extends StatelessWidget {
  const _InvitePanel({required this.church, required this.role});

  final String church;
  final String role;

  static const _can = {
    'pastor': [
      (true, 'Approve and record giving'),
      (true, 'See every partner, fellowship and report'),
      (true, 'Invite and manage people'),
    ],
    'admin': [
      (true, 'Set up arms, periods and fellowships'),
      (true, 'Invite and manage people'),
      (false, 'See giving · pastors and staff do this'),
    ],
    'staff': [
      (true, 'Record giving and bring in sheets'),
      (true, 'See partners and fellowships'),
      (false, 'Approve entries · pastors and admins do this'),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final compact = AuthPanelScope.of(context);
    final roleName = role.isEmpty
        ? 'Staff'
        : role[0].toUpperCase() + role.substring(1).toLowerCase();
    final words = church.trim().split(RegExp(r'\s+'));
    final initials = words.take(2).map((w) => w[0].toUpperCase()).join();
    final ticket = Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Sel.card,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Sel.skyWash,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  initials,
                  style: SelType.subtitle.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: SelSpace.x4),
              Expanded(
                child: Text(
                  church,
                  style: SelType.subtitle.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: SelSpace.x4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Sel.ink,
              borderRadius: BorderRadius.circular(SelRadius.pill),
            ),
            child: Text(roleName, style: SelType.tag.copyWith(color: Sel.card)),
          ),
          const SizedBox(height: SelSpace.x4),
          const Divider(color: Sel.border),
          const SizedBox(height: SelSpace.x3),
          Text('As $roleName you can', style: SelType.bodyMedium),
          const SizedBox(height: SelSpace.x3),
          for (final (yes, label) in _can[role.toLowerCase()] ?? _can['staff']!)
            Padding(
              padding: const EdgeInsets.only(bottom: SelSpace.x2),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: yes ? Sel.successWash : Sel.track,
                    ),
                    child: Icon(
                      yes ? LucideIcons.check : LucideIcons.x,
                      size: 15,
                      color: yes ? Sel.success : Sel.warm,
                    ),
                  ),
                  const SizedBox(width: SelSpace.x3),
                  Expanded(
                    child: Text(
                      label,
                      style: SelType.body.copyWith(
                        color: yes ? Sel.text : Sel.warm,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthPanelLogo(),
        SizedBox(height: compact ? SelSpace.x4 : SelSpace.x10),
        AuthPanelHeadline(
          title: "You're invited to $church",
          body:
              'You were added as $roleName. Set up your account and '
              "you're in.",
        ),
        if (!compact) ...[Expanded(child: Center(child: ticket))],
      ],
    );
  }
}
