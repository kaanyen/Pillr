import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/extensions/async_value_ext.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/router/church_tenant_gate_cache.dart';
import '../../../core/router/user_church_index_cache.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/validation_utils.dart';
import '../providers/auth_providers.dart';
import 'widgets/auth_field_decoration.dart';
import 'widgets/auth_primary_button.dart';
import 'widgets/auth_split_shell.dart';

class _CurrencyOption {
  const _CurrencyOption(this.code, this.symbol, this.label);
  final String code;
  final String symbol;
  final String label;
}

const _currencies = <_CurrencyOption>[
  _CurrencyOption('GHS', '\u20B5', 'Ghana cedi (GHS)'),
  _CurrencyOption('USD', r'$', 'US dollar (USD)'),
  _CurrencyOption('EUR', '\u20AC', 'Euro (EUR)'),
  _CurrencyOption('GBP', '\u00A3', 'British pound (GBP)'),
];

class BootstrapJoinScreen extends ConsumerStatefulWidget {
  const BootstrapJoinScreen({super.key, this.prefilledCode});

  final String? prefilledCode;

  @override
  ConsumerState<BootstrapJoinScreen> createState() => _BootstrapJoinScreenState();
}

class _BootstrapJoinScreenState extends ConsumerState<BootstrapJoinScreen> {
  int _step = 1;
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _churchName = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();

  String? _validatedRole;
  String _currencyCode = 'GHS';
  String? _error;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscurePassword2 = true;

  @override
  void initState() {
    super.initState();
    if (widget.prefilledCode != null) {
      _code.text = widget.prefilledCode!.toUpperCase();
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _name.dispose();
    _phone.dispose();
    _churchName.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    if (!isValidEmail(_email.text)) {
      setState(() {
        _error = 'Enter a valid email.';
        _loading = false;
      });
      return;
    }
    if (_code.text.trim().length < 6) {
      setState(() {
        _error = 'Enter your setup code.';
        _loading = false;
      });
      return;
    }
    final res = await ref.read(authRepositoryProvider).validateBootstrapInvite(
          email: _email.text,
          code: _code.text,
        );
    setState(() {
      _loading = false;
      if (!res.valid) {
        _error = res.errorMessage ?? 'Setup code could not be verified.';
        return;
      }
      _validatedRole = res.role;
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

    setState(() => _loading = true);
    final authRepo = ref.read(authRepositoryProvider);
    final email = _email.text.trim();
    var createdFreshAccount = false;
    try {
      try {
        await authRepo.createAuthUser(email: email, password: _password.text);
        createdFreshAccount = true;
      } on FirebaseAuthException catch (e) {
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
      setState(() => _error = humanizeAuthException(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onBack() {
    if (_step == 2) {
      setState(() {
        _step = 1;
        _error = null;
      });
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user != null && idx != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/dashboard');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AuthSplitShell(
      formChild: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: _step == 2 ? 'Back' : 'Back to home',
                icon: const Icon(LucideIcons.arrowLeft, size: 22),
                onPressed: _onBack,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_step == 1) _buildStep1() else _buildStep2(),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create your church',
          style: AppTypography.heading,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Enter the email and setup code from your Pillr invitation.',
          style: AppTypography.body.copyWith(color: AppColors.smoke, height: 1.45),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: authCardInputDecoration(hintText: 'Email'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: authCardInputDecoration(hintText: 'Setup code'),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(_error!, style: AppTypography.body.copyWith(color: AppColors.ink)),
        ],
        const SizedBox(height: AppSpacing.lg),
        AuthPrimaryButton(
          label: 'Continue',
          loading: _loading,
          onPressed: _loading ? null : _verify,
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your profile & church',
          style: AppTypography.heading,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _validatedRole != null
              ? 'You will join as ${_validatedRole == 'admin' ? 'church admin' : 'pastor'}.'
              : '',
          style: AppTypography.body.copyWith(color: AppColors.smoke, height: 1.45),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: authCardInputDecoration(hintText: 'Full name'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: authCardInputDecoration(hintText: 'Phone (optional)'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _churchName,
          textCapitalization: TextCapitalization.words,
          decoration: authCardInputDecoration(hintText: 'Church display name'),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: _currencyCode,
          decoration: authCardInputDecoration(hintText: 'Currency'),
          items: [
            for (final c in _currencies)
              DropdownMenuItem(value: c.code, child: Text(c.label)),
          ],
          onChanged: (v) => setState(() => _currencyCode = v ?? 'GHS'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _password,
          obscureText: _obscurePassword,
          decoration: authCardInputDecoration(hintText: 'Password').copyWith(
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _password2,
          obscureText: _obscurePassword2,
          decoration: authCardInputDecoration(hintText: 'Confirm password').copyWith(
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword2 ? LucideIcons.eye : LucideIcons.eyeOff),
              onPressed: () => setState(() => _obscurePassword2 = !_obscurePassword2),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(_error!, style: AppTypography.body.copyWith(color: AppColors.ink)),
        ],
        const SizedBox(height: AppSpacing.lg),
        AuthPrimaryButton(
          label: 'Create workspace',
          loading: _loading,
          onPressed: _loading ? null : _submit,
        ),
      ],
    );
  }
}
