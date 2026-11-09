import '../errors/plain_error.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../design/seline.dart';

enum SelNoticeKind { info, success, error }

class SelNoticeItem {
  SelNoticeItem({
    required this.id,
    required this.message,
    required this.kind,
    required this.createdAt,
  });

  final String id;
  final String message;
  final SelNoticeKind kind;
  final DateTime createdAt;
}

class SelNoticeController extends Notifier<List<SelNoticeItem>> {
  static const _maxVisible = 4;
  static const _defaultDuration = Duration(seconds: 5);
  final _timers = <String, Timer>{};
  var _seq = 0;

  @override
  List<SelNoticeItem> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    return const [];
  }

  void show(
    String message, {
    SelNoticeKind kind = SelNoticeKind.info,
    Duration duration = _defaultDuration,
  }) {
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
    final item = SelNoticeItem(
      id: id,
      message: message,
      kind: kind,
      createdAt: DateTime.now(),
    );
    state = [item, ...state].take(_maxVisible).toList();
    _timers[id]?.cancel();
    _timers[id] = Timer(duration, () => dismiss(id));
  }

  void dismiss(String id) {
    _timers.remove(id)?.cancel();
    state = state.where((item) => item.id != id).toList();
  }
}

final selNoticeControllerProvider =
    NotifierProvider<SelNoticeController, List<SelNoticeItem>>(
  SelNoticeController.new,
);

void selNotice(
  BuildContext context,
  String message, {
  SelNoticeKind kind = SelNoticeKind.info,
  Duration duration = SelNoticeDuration.standard,
}) {
  // A problem is always said in plain words, never as a code or class name.
  final text = kind == SelNoticeKind.error ? plainErrorText(message) : message;
  ProviderScope.containerOf(context, listen: false)
      .read(selNoticeControllerProvider.notifier)
      .show(text, kind: kind, duration: duration);
}

abstract final class SelNoticeDuration {
  static const standard = Duration(seconds: 5);
}

/// Top-right notification stack — replaces transient SnackBars app-wide.
class SelNoticeHost extends ConsumerWidget {
  const SelNoticeHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(selNoticeControllerProvider);
    final compact = MediaQuery.sizeOf(context).width < 900;

    return Stack(
      children: [
        child,
        Positioned(
          top: compact ? SelSpace.x12 : SelSpace.x16,
          right: compact ? SelSpace.x4 : SelSpace.x8,
          child: IgnorePointer(
            ignoring: items.isEmpty,
            child: AnimatedOpacity(
              opacity: items.isEmpty ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compact ? 320 : 360,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: SelSpace.x2),
                        child: _NoticeCard(
                          item: item,
                          onDismiss: () => ref
                              .read(selNoticeControllerProvider.notifier)
                              .dismiss(item.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoticeCard extends StatefulWidget {
  const _NoticeCard({required this.item, required this.onDismiss});

  final SelNoticeItem item;
  final VoidCallback onDismiss;

  @override
  State<_NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<_NoticeCard> {
  bool _hover = false;

  IconData get _icon => switch (widget.item.kind) {
        SelNoticeKind.success => LucideIcons.checkCircle2,
        SelNoticeKind.error => LucideIcons.alertCircle,
        SelNoticeKind.info => LucideIcons.info,
      };

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Sel.card,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SelRadius.card),
          side: const BorderSide(color: Sel.border),
        ),
        child: InkWell(
          onTap: widget.onDismiss,
          borderRadius: BorderRadius.circular(SelRadius.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SelSpace.x4,
              vertical: SelSpace.x3,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon, size: 16, color: Sel.ink),
                const SizedBox(width: SelSpace.x3),
                Expanded(
                  child: Text(
                    widget.item.message,
                    style: SelType.bodySm.copyWith(
                      color: Sel.ink,
                      height: 1.35,
                    ),
                  ),
                ),
                if (_hover) ...[
                  const SizedBox(width: SelSpace.x2),
                  Icon(LucideIcons.x, size: 14, color: Sel.ash),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
