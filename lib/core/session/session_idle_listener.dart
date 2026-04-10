import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../extensions/async_value_ext.dart';
import '../../features/auth/providers/auth_providers.dart';

/// Signs the user out after [idleDuration] with no pointer, scroll, or keyboard activity.
/// Only active while [User] is non-null.
class SessionIdleListener extends ConsumerStatefulWidget {
  const SessionIdleListener({
    super.key,
    required this.child,
    this.idleDuration = const Duration(minutes: 10),
  });

  final Widget child;
  final Duration idleDuration;

  @override
  ConsumerState<SessionIdleListener> createState() => _SessionIdleListenerState();
}

class _SessionIdleListenerState extends ConsumerState<SessionIdleListener> {
  Timer? _idleTimer;
  late final bool Function(KeyEvent) _keyHandler;

  @override
  void initState() {
    super.initState();
    _keyHandler = (KeyEvent event) {
      _bumpActivity();
      return false;
    };
    HardwareKeyboard.instance.addHandler(_keyHandler);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(authStateProvider).valueOrNull != null) {
        _armOrCancelTimer();
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_keyHandler);
    _idleTimer?.cancel();
    super.dispose();
  }

  void _armOrCancelTimer() {
    _idleTimer?.cancel();
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    _idleTimer = Timer(widget.idleDuration, _onIdle);
  }

  void _bumpActivity() {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    _armOrCancelTimer();
  }

  Future<void> _onIdle() async {
    if (!mounted) return;
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Signed out after a period of inactivity.')),
    );

    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (prev, next) {
      if (next.isLoading) return;
      final user = next.valueOrNull;
      if (user != null) {
        _armOrCancelTimer();
      } else {
        _idleTimer?.cancel();
      }
    });

    final signedIn = ref.watch(authStateProvider).valueOrNull != null;
    if (!signedIn) {
      return widget.child;
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification ||
            n is ScrollUpdateNotification ||
            n is OverscrollNotification) {
          _bumpActivity();
        }
        return false;
      },
      child: MouseRegion(
        onHover: (_) => _bumpActivity(),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _bumpActivity(),
          onPointerSignal: (_) => _bumpActivity(),
          child: widget.child,
        ),
      ),
    );
  }
}
