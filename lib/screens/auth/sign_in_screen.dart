import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/errors/error_handler.dart';
import '../../core/utils/validation_utils.dart';
import '../../design/seline.dart';
import '../../features/auth/providers/auth_providers.dart';
import 'auth_shell.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _error = null;
      _notice = null;
    });
    if (!isValidEmail(_email.text)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = 'Password is required.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).signInWithEmail(
            email: _email.text.trim(),
            password: _password.text,
          );
      if (mounted) context.go('/overview');
    } catch (e) {
      if (mounted) setState(() => _error = humanizeAuthException(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    if (!isValidEmail(_email.text)) {
      setState(() => _error = 'Enter your email above, then tap Forgot password.');
      return;
    }
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordResetEmail(_email.text);
      if (mounted) {
        setState(() => _notice = 'Password reset sent to ${_email.text.trim()}.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = humanizeAuthException(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Welcome back',
      subtitle: 'Sign in to your church workspace.',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Have an invite code instead? '),
          GestureDetector(
            onTap: () => context.go('/join'),
            child: Text(
              'Join a church',
              style: SelType.small.copyWith(
                color: Sel.cyanEdge,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) AuthNotice(message: _error!),
          if (_notice != null) AuthNotice(message: _notice!),
          SelField(
            controller: _email,
            label: 'Email',
            hint: 'you@church.org',
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            prefixIcon: LucideIcons.mail,
          ),
          const SizedBox(height: SelSpace.x4),
          SelField(
            controller: _password,
            label: 'Password',
            hint: 'Your password',
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            prefixIcon: LucideIcons.lock,
            onSubmitted: (_) => _submit(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                size: 15,
                color: Sel.ash,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: SelSpace.x3),
          Align(
            alignment: Alignment.centerRight,
            child: SelButton(
              label: 'Forgot password?',
              kind: SelButtonKind.quiet,
              dense: true,
              onPressed: _forgot,
            ),
          ),
          const SizedBox(height: SelSpace.x4),
          SelButton.cyan(
            label: 'Sign in',
            expanded: true,
            loading: _busy,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
