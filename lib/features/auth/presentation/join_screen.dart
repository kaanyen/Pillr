import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:lucide_icons/lucide_icons.dart';

import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_text_field.dart';
import '../../../core/extensions/async_value_ext.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/validation_utils.dart';
import '../domain/invite_models.dart';
import '../providers/auth_providers.dart';
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
      if (mounted) context.go('/dashboard');
    } catch (e) {
      setState(() => _error = humanizeAuthException(e));
    } finally {
      if (mounted) setState(() => _loading = false);
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

    final form = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl + 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to sign in',
                icon: const Icon(LucideIcons.arrowLeft, size: 22),
                onPressed: () => context.go('/login'),
              ),
              Text(
                'Join Pillr',
                style: AppTypography.heading3,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/login'),
                child: Text(
                  'Sign in',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_step == 1) _buildStep1() else _buildStep2(),
        ],
      ),
    );

    return Scaffold(
      body: AuthSplitShell(form: form),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "You've been invited",
          style: AppTypography.heading1,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Enter the email that received the invite and your 8-character code.',
          style: AppTypography.body,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_error != null)
          Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.dangerColor)),
        const SizedBox(height: AppSpacing.md),
        PillrTextField(
          controller: _email,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: AppSpacing.md),
        PillrTextField(
          controller: _code,
          label: 'Invite code',
          textCapitalization: TextCapitalization.characters,
          onChanged: (v) {
            _code.value = TextEditingValue(
              text: v.toUpperCase(),
              selection: _code.selection,
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        PillrButton(
          label: 'Verify invitation',
          expanded: true,
          loading: _loading,
          onPressed: _loading ? null : _verifyInvite,
          variant: PillrButtonVariant.primary,
        ),
      ],
    );
  }

  Widget _buildStep2() {
    final church = _validated?.churchName ?? 'your church';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Welcome to $church', style: AppTypography.heading1),
        const SizedBox(height: AppSpacing.sm),
        Text('Complete your profile to finish registration.', style: AppTypography.body),
        const SizedBox(height: AppSpacing.lg),
        if (_error != null)
          Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.dangerColor)),
        const SizedBox(height: AppSpacing.md),
        PillrTextField(controller: _name, label: 'Full name'),
        const SizedBox(height: AppSpacing.md),
        PillrTextField(
          controller: _phone,
          label: 'Phone',
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: AppSpacing.md),
        PillrTextField(
          controller: _password,
          label: 'Password',
          obscureText: true,
        ),
        const SizedBox(height: AppSpacing.md),
        PillrTextField(
          controller: _password2,
          label: 'Confirm password',
          obscureText: true,
        ),
        const SizedBox(height: AppSpacing.lg),
        PillrButton(
          label: 'Create account',
          expanded: true,
          loading: _loading,
          onPressed: _loading ? null : _createAccount,
          variant: PillrButtonVariant.primary,
        ),
      ],
    );
  }
}
