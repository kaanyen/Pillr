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
import '../domain/invite_models.dart';
import '../providers/auth_providers.dart';
import 'widgets/auth_field_decoration.dart';
import 'widgets/auth_primary_button.dart';
import 'widgets/auth_split_shell.dart';

class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, this.prefilledCode});

  final String? prefilledCode;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  int _step = 1;
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();

  InviteValidationResult? _validated;
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
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _verifyInvite() async {
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
        _error = 'Enter your invite code.';
        _loading = false;
      });
      return;
    }
    final res = await ref.read(authRepositoryProvider).validateInvite(
          email: _email.text,
          code: _code.text,
        );
    setState(() {
      _loading = false;
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

    setState(() => _loading = true);
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
        await auth.deleteCurrentUser();
        rethrow;
      }
      if (mounted) {
        UserChurchIndexCache.clear();
        ChurchTenantGateCache.clear();
        context.go('/overview');
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
        if (context.mounted) context.go('/overview');
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
          'Get started',
          style: AppTypography.heading,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Verify your church invitation — enter the email and code you received.',
          style: AppTypography.body.copyWith(
            color: AppColors.smoke,
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.ink)),
          ),
        Text('Email', style: AppTypography.label.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink)),
        const SizedBox(height: 8),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: authCardInputDecoration(hintText: 'Enter your email'),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Invite code', style: AppTypography.label.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink)),
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: authCardInputDecoration(hintText: 'Enter your code'),
          onChanged: (v) {
            _code.value = TextEditingValue(
              text: v.toUpperCase(),
              selection: _code.selection,
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthPrimaryButton(
          label: 'Continue',
          loading: _loading,
          onPressed: _verifyInvite,
        ),
        const SizedBox(height: AppSpacing.xl),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              Text(
                'Have an account?',
                style: AppTypography.caption.copyWith(color: AppColors.smoke),
              ),
              TextButton(
                onPressed: () => context.go('/sign-in'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Login',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    final church = _validated?.churchName ?? 'your church';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create your account',
          style: AppTypography.heading,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Welcome to $church — finish your profile to continue.',
          style: AppTypography.body.copyWith(
            color: AppColors.smoke,
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.ink)),
          ),
        Text('Full name', style: AppTypography.label.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink)),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          decoration: authCardInputDecoration(hintText: 'Full name'),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Phone', style: AppTypography.label.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink)),
        const SizedBox(height: 8),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: authCardInputDecoration(hintText: 'Phone number'),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Password', style: AppTypography.label.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink)),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          obscureText: _obscurePassword,
          decoration: authCardInputDecoration(
            hintText: 'At least 8 characters',
            suffixIcon: IconButton(
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
                color: AppColors.pewter,
                size: 20,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Confirm password', style: AppTypography.label.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink)),
        const SizedBox(height: 8),
        TextField(
          controller: _password2,
          obscureText: _obscurePassword2,
          decoration: authCardInputDecoration(
            hintText: 'Repeat password',
            suffixIcon: IconButton(
              tooltip: _obscurePassword2 ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscurePassword2 = !_obscurePassword2),
              icon: Icon(
                _obscurePassword2 ? LucideIcons.eye : LucideIcons.eyeOff,
                color: AppColors.pewter,
                size: 20,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthPrimaryButton(
          label: 'Sign up',
          loading: _loading,
          onPressed: _createAccount,
        ),
        const SizedBox(height: AppSpacing.xl),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              Text(
                'Have an account?',
                style: AppTypography.caption.copyWith(color: AppColors.smoke),
              ),
              TextButton(
                onPressed: () => context.go('/sign-in'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Login',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
