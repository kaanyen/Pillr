import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/pillr_button.dart';
import '../../../common/widgets/pillr_card.dart';
import '../../../common/widgets/pillr_text_field.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/pillr_layout.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/validation_utils.dart';
import '../providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
    });
    if (!isValidEmail(_email.text)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = 'Password is required.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).signInWithEmail(
            email: _email.text,
            password: _password.text,
          );
      if (mounted) context.go('/dashboard');
    } catch (e) {
      setState(() => _error = humanizeAuthException(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgot() async {
    if (!isValidEmail(_email.text)) {
      setState(() => _error = 'Enter your email above, then tap Forgot password.');
      return;
    }
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(_email.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent.')),
        );
      }
    } catch (e) {
      setState(() => _error = humanizeAuthException(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: AppColors.surfaceColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: size.width > 480 ? PillrLayout.formMaxWidth : double.infinity),
            child: PillrCard(
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Pillr', style: AppTypography.display.copyWith(fontSize: 28)),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Sign in to your church workspace.',
                      style: AppTypography.body,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_error != null) ...[
                      Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.dangerColor)),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    PillrTextField(
                      controller: _email,
                      label: 'Email',
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PillrTextField(
                      controller: _password,
                      label: 'Password',
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: PillrButton(
                        label: 'Forgot password?',
                        variant: PillrButtonVariant.ghost,
                        onPressed: _loading ? null : _forgot,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PillrButton(
                      label: 'Sign in',
                      expanded: true,
                      loading: _loading,
                      onPressed: _loading ? null : _submit,
                      variant: PillrButtonVariant.primary,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Have an invite? ', style: AppTypography.body),
                        PillrButton(
                          label: 'Join',
                          variant: PillrButtonVariant.ghost,
                          onPressed: () => context.go('/join'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
