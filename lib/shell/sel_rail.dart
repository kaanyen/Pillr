import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/extensions/async_value_ext.dart';
import '../design/seline.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/church/providers/church_settings_providers.dart';
import '../features/entries/providers/entries_providers.dart';
import '../features/platform/providers/platform_providers.dart';
import '../l10n/app_localizations.dart';
import 'nav_model.dart';

/// The bare canvas rail.
///
/// There is deliberately **no surface here** — no fill, no border, no divider,
/// no card. The links sit directly on the warm page like margin notes, and the
/// only thing that separates navigation from content is whitespace and the
/// fact that content lives inside white cards. Removing the sidebar *as a
/// panel* is what makes the layout read as paper rather than as an app chrome.
///
/// The active row is the one exception: it gets a white card fill, so the
/// selected destination looks like it has been lifted onto the same plane as
/// the content it is showing.
class SelRail extends ConsumerWidget {
  const SelRail({super.key, required this.currentPath});

  final String currentPath;

  bool _isActive(String path) {
    if (currentPath == path) return true;
    return path != '/overview' && currentPath.startsWith('$path/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    final churchName = ref.watch(churchNameProvider) ?? 'Your church';
    final profile = ref.watch(churchUserProfileProvider).valueOrNull;
    final pending = ref.watch(pendingApprovalCountProvider);
    final isPlatform = ref.watch(isPlatformAdminProvider).valueOrNull == true;

    final groups = navGroupsFor(
      idx,
      AppLocalizations.of(context),
      platformAdmin: isPlatform,
    );

    return SizedBox(
      width: SelLayout.railWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wordmark — spark glyph + name, per the reference's compact lockup.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SelSpace.x3,
              SelSpace.x6,
              SelSpace.x3,
              SelSpace.x2,
            ),
            child: Row(
              children: [
                const PillrLogo(height: 22),
                const SizedBox(width: SelSpace.x2),
                Expanded(
                  child: Text(
                    'The Pillr',
                    style: SelType.bodyMedium.copyWith(color: Sel.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SelSpace.x3,
              0,
              SelSpace.x3,
              SelSpace.x6,
            ),
            child: Text(
              churchName,
              style: SelType.small,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final g in groups) ...[
                  if (g.title != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        SelSpace.x3,
                        SelSpace.x6,
                        SelSpace.x3,
                        SelSpace.x2,
                      ),
                      child: Text(
                        g.title!.toUpperCase(),
                        style: SelType.caption,
                      ),
                    )
                  else
                    const SizedBox(height: SelSpace.x2),
                  for (final item in g.items)
                    if (item.children.isEmpty)
                      _RailLink(
                        item: item,
                        active: _isActive(item.path),
                        badge: item.badgeKey == 'pending' ? pending : null,
                        onTap: () => context.go(item.path),
                      )
                    else
                      _RailSection(
                        item: item,
                        currentPath: currentPath,
                        badge: item.badgeKey == 'pending' ? pending : null,
                        onNavigate: context.go,
                      ),
                ],
              ],
            ),
          ),

          if (profile != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SelSpace.x3,
                SelSpace.x4,
                SelSpace.x3,
                SelSpace.x6,
              ),
              child: Row(
                children: [
                  Container(
                    height: 24,
                    width: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Sel.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: Sel.border),
                    ),
                    child: Text(
                      profile.fullName.isNotEmpty
                          ? profile.fullName[0].toUpperCase()
                          : '?',
                      style: SelType.small.copyWith(
                        color: Sel.ink,
                        fontWeight: FontWeight.w500,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: SelSpace.x2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          profile.fullName,
                          style: SelType.small.copyWith(
                            color: Sel.ink,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          profile.role[0].toUpperCase() +
                              profile.role.substring(1),
                          style: SelType.small.copyWith(fontSize: 11),
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A parent nav item with indented sub-links — one lifted card for the active
/// child, not a stack of separate boxes.
class _RailSection extends StatelessWidget {
  const _RailSection({
    required this.item,
    required this.currentPath,
    required this.onNavigate,
    this.badge,
  });

  final SelNavItem item;
  final String currentPath;
  final void Function(String location) onNavigate;
  final int? badge;

  bool get _expanded =>
      currentPath == item.path || currentPath.startsWith('${item.path}/');

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return _RailLink(
        item: item,
        active: false,
        badge: badge,
        onTap: () => onNavigate(item.path),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: SelSpace.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RailSectionHeader(
            item: item,
            badge: badge,
            onTap: () => onNavigate(item.path),
          ),
          for (final child in item.children)
            _RailSubLink(
              label: child.label,
              active: currentPath == child.path,
              onTap: () => onNavigate(child.path),
            ),
        ],
      ),
    );
  }
}

class _RailSectionHeader extends StatefulWidget {
  const _RailSectionHeader({
    required this.item,
    required this.onTap,
    this.badge,
  });

  final SelNavItem item;
  final VoidCallback onTap;
  final int? badge;

  @override
  State<_RailSectionHeader> createState() => _RailSectionHeaderState();
}

class _RailSectionHeaderState extends State<_RailSectionHeader> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: SelFocusRing(
            focused: _focused,
            radius: SelRadius.input,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: SelLayout.tapTarget),
              child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SelSpace.x3,
              vertical: SelSpace.x2,
            ),
            child: Row(
              children: [
                Icon(
                  widget.item.icon,
                  size: 15,
                  color: _hover ? Sel.ink : Sel.warm,
                ),
                const SizedBox(width: SelSpace.x2 + 2),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: SelType.body.copyWith(
                      color: _hover ? Sel.ink : Sel.warm,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.badge != null && widget.badge! > 0)
                  SelCountTag(label: '${widget.badge}', emphasised: true),
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

/// A rail link. At rest it is warm-gray text on bare canvas. Active, it gets a
/// white card fill so it reads as continuous with the content beside it.
class _RailLink extends StatefulWidget {
  const _RailLink({
    required this.item,
    required this.active,
    required this.onTap,
    this.badge,
  });

  final SelNavItem item;
  final bool active;
  final VoidCallback onTap;
  final int? badge;

  @override
  State<_RailLink> createState() => _RailLinkState();
}

class _RailLinkState extends State<_RailLink> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final fg = active ? Sel.ink : (_hover ? Sel.ink : Sel.warm);

    return Semantics(
      link: true,
      selected: active,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (v) => setState(() => _hover = v),
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: widget.onTap,
            child: SelFocusRing(
              focused: _focused,
              radius: SelRadius.input,
              child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              constraints: const BoxConstraints(minHeight: SelLayout.tapTarget),
              padding: const EdgeInsets.symmetric(
                horizontal: SelSpace.x3,
                vertical: SelSpace.x2,
              ),
              decoration: BoxDecoration(
                color: active
                    ? Sel.card
                    : _hover
                    ? Sel.card.withValues(alpha: 0.6)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(SelRadius.input),
                border: Border.all(
                  color: active ? Sel.border : Colors.transparent,
                ),
                boxShadow: active ? SelShadow.hairline : null,
              ),
              child: Row(
                children: [
                  Icon(widget.item.icon, size: 15, color: fg),
                  const SizedBox(width: SelSpace.x2 + 2),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      style: SelType.body.copyWith(
                        color: fg,
                        fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.badge != null && widget.badge! > 0)
                    SelCountTag(label: '${widget.badge}', emphasised: active),
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

class _RailSubLink extends StatefulWidget {
  const _RailSubLink({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_RailSubLink> createState() => _RailSubLinkState();
}

class _RailSubLinkState extends State<_RailSubLink> {
  bool _hover = false;
  bool _focused = false;

  static const _iconColumn = 15.0 + SelSpace.x2 + 2;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final fg = active ? Sel.ink : (_hover ? Sel.ink : Sel.warm);

    return Semantics(
      link: true,
      selected: active,
      child: Padding(
        padding: const EdgeInsets.only(
          left: SelSpace.x3,
          right: SelSpace.x3,
          bottom: 1,
        ),
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (v) => setState(() => _hover = v),
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: widget.onTap,
            child: SelFocusRing(
              focused: _focused,
              radius: SelRadius.input,
              child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              constraints: const BoxConstraints(minHeight: SelLayout.tapTarget),
              padding: EdgeInsets.fromLTRB(
                _iconColumn + SelSpace.x2,
                SelSpace.x2,
                SelSpace.x3,
                SelSpace.x2,
              ),
              decoration: BoxDecoration(
                color: active
                    ? Sel.card
                    : _hover
                        ? Sel.card.withValues(alpha: 0.45)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(SelRadius.input),
                border: Border.all(
                  color: active ? Sel.border : Colors.transparent,
                ),
                boxShadow: active ? SelShadow.hairline : null,
              ),
              child: Text(
                widget.label,
                style: SelType.small.copyWith(
                  color: fg,
                  fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}
