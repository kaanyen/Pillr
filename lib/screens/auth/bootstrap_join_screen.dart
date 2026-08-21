import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/errors/error_handler.dart';
import '../../core/router/church_tenant_gate_cache.dart';
import '../../core/router/user_church_index_cache.dart';
import '../../core/utils/validation_utils.dart';
import '../../design/seline.dart';
import '../../features/auth/providers/auth_providers.dart';
import 'auth_shell.dart';

class _Currency {
  const _Currency(this.code, this.symbol, this.label);
  final String code;
  final String symbol;
  final String label;
}

const _currencies = <_Currency>[
  _Currency('GHS', '₵', 'Ghana cedi (GHS)'),
  _Currency('USD', r'$', 'US dollar (USD)'),
  _Currency('EUR', '€', 'Euro (EUR)'),
  _Currency('GBP', '£', 'British pound (GBP)'),
];

/// Bootstrap join — the first user of a brand-new church redeems a platform
/// setup code and creates the workspace in the same pass.
class BootstrapJoinScreen extends ConsumerStatefulWidget {
  const BootstrapJoinScreen({super.key, this.prefilledCode});

  /// Code lifted from the invite email link (`?code=…`).
  final String? prefilledCode;

  @override
  ConsumerState<BootstrapJoinScreen> createState() => _BootstrapJoinScreenState();
}

class _BootstrapJoinScreenState extends ConsumerState<BootstrapJoinScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _churchName = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();

  int _step = 1;
  bool _busy = false;
  String? _error;
  String _currencyCode = 'GHS';

  @override
  void initState() {
    super.initState();
    if (widget.prefilledCode != null && widget.prefilledCode!.isNotEmpty) {
      _code.text = widget.prefilledCode!.toUpperCase();
    }
  }

  @override
  void dispose() {
    for (final c in [
      _email, _code, _name, _phone, _churchName, _password, _password2,
    ]) {
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
      setState(() => _error = 'Enter your setup code.');
      return;
    }
    setState(() => _busy = true);
    final res = await ref
        .read(authRepositoryProvider)
        .validateBootstrapInvite(email: _email.text, code: _code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!res.valid) {
        _error = res.errorMessage ?? 'Setup code could not be verified.';
        return;
      }
      _step = 2;
    });
  }

  Future<void> _submit() async {
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
    if (_name.text.trim().isEmpty || _churchName.text.trim().isEmpty) {
      setState(() => _error = 'Full name and church name are required.');
      return;
    }

    setState(() => _busy = true);
    final authRepo = ref.read(authRepositoryProvider);
    final email = _email.text.trim();
    var createdFreshAccount = false;
    try {
      try {
        await authRepo.createAuthUser(email: email, password: _password.text);
        createdFreshAccount = true;
      } on FirebaseAuthException catch (e) {
        // Someone who already has an account may still be redeeming a setup
        // code for a new church — sign them in rather than failing.
        if (e.code == 'email-already-in-use') {
          await authRepo.signInWithEmail(email: email, password: _password.text);
        } else {
          rethrow;
        }
      }
      final cur = _currencies.firstWhere((c) => c.code == _currencyCode);
      try {
        await authRepo.redeemBootstrapInvite(
          fullName: _name.text,
          phone: _phone.text,
          code: _code.text,
          churchName: _churchName.text,
          currency: cur.code,
          currencySymbol: cur.symbol,
        );
      } catch (_) {
        if (createdFreshAccount) {
          await FirebaseAuth.instance.currentUser?.delete();
        }
        rethrow;
      }
      if (mounted) {
        UserChurchIndexCache.clear();
        ChurchTenantGateCache.clear();
        context.go('/onboarding');
      }
    } catch (e) {
      if (mounted) setState(() => _error = humanizeAuthException(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      width: 440,
      title: _step == 1 ? 'Set up a new ' : 'Name your ',
      highlight: _step == 1 ? 'workspace' : 'church',
      subtitle: _step == 1
          ? 'Enter the email your setup code was sent to.'
          : 'This is what your team will see when they sign in.',
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
          if (_error != null) AuthNotice(message: _error!),
          if (_step == 1) ...[
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
              label: 'Setup code',
              hint: 'ABCD123456',
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
          ] else ...[
            SelField(
              controller: _churchName,
              label: 'Church name',
              hint: 'Grace Community Church',
            ),
            const SizedBox(height: SelSpace.x4),
            SelSelect<String>(
              value: _currencyCode,
              label: 'Currency',
              onChanged: (v) => setState(() => _currencyCode = v ?? 'GHS'),
              items: [
                for (final c in _currencies)
                  DropdownMenuItem(value: c.code, child: Text(c.label)),
              ],
            ),
            const SizedBox(height: SelSpace.x6),
            const Divider(height: 1, color: Sel.border),
            const SizedBox(height: SelSpace.x6),
            SelField(controller: _name, label: 'Your full name', hint: 'Ama Boateng'),
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
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: SelSpace.x6),
            SelButton.cyan(
              label: 'Create workspace',
              expanded: true,
              loading: _busy,
              onPressed: _submit,
            ),
          ],
        ],
      ),
    );
  }
}
