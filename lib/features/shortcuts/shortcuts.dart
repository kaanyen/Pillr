import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/extensions/async_value_ext.dart';
import '../auth/providers/auth_providers.dart';

/// One page a person can pin to the top of Overview.
///
/// Shortcuts only ever open pages — never one fellowship or one group — so the
/// list stays the same for every church.
@immutable
class Shortcut {
  const Shortcut(
    this.id,
    this.group,
    this.label,
    this.hint,
    this.icon,
    this.path, {
    this.pastorOnly = false,
  });

  final String id;
  final String group;
  final String label;
  final String hint;
  final IconData icon;
  final String path;
  final bool pastorOnly;
}

/// Everything that can be pinned, grouped the way the sidebar is.
const shortcutCatalog = <Shortcut>[
  Shortcut(
    'record',
    'Do',
    'Record giving',
    'Opens the form',
    LucideIcons.pencil,
    '/entries/new',
  ),
  Shortcut(
    'import',
    'Do',
    'Bring in a sheet',
    'Excel or CSV',
    LucideIcons.sheet,
    '/entries/bulk-import',
  ),
  Shortcut(
    'queue',
    'Do',
    'Queue',
    'Entries waiting',
    LucideIcons.inbox,
    '/queue',
  ),
  Shortcut(
    'records',
    'Records',
    'All records',
    'Every entry',
    LucideIcons.fileText,
    '/records',
  ),
  Shortcut(
    'monthly',
    'Records',
    'By month',
    'Month by month',
    LucideIcons.calendar,
    '/records/monthly',
  ),
  Shortcut(
    'by-arm',
    'Records',
    'By arm',
    'Each main arm',
    LucideIcons.barChart3,
    '/records/by-arm',
  ),
  Shortcut(
    'by-fellowship',
    'Records',
    'By fellowship',
    'Every fellowship',
    LucideIcons.users2,
    '/records/by-fellowship',
  ),
  Shortcut(
    'by-partner',
    'Records',
    'By partner',
    "Each partner's year",
    LucideIcons.user,
    '/records/by-partner',
  ),
  Shortcut(
    'imports',
    'Records',
    'Imports',
    'Sheets brought in',
    LucideIcons.fileUp,
    '/records/imports',
  ),
  Shortcut(
    'partners',
    'Partners',
    'All partners',
    'The directory',
    LucideIcons.users,
    '/partners',
  ),
  Shortcut(
    'partners-grouped',
    'Partners',
    'Partners by fellowship',
    'Grouped',
    LucideIcons.users2,
    '/partners/by-fellowship',
  ),
  Shortcut(
    'new-partners',
    'Partners',
    'New this year',
    'Added this period',
    LucideIcons.userPlus,
    '/partners/new',
  ),
  Shortcut(
    'rhythm',
    'Partners',
    'Giving rhythm',
    'Who gives when',
    LucideIcons.activity,
    '/partners/rhythm',
  ),
  Shortcut(
    'follow-up',
    'Partners',
    'Follow up',
    'Gone quiet',
    LucideIcons.phoneCall,
    '/partners/follow-up',
  ),
  Shortcut(
    'ranked',
    'Partners',
    'Ranked',
    'By approved giving',
    LucideIcons.trophy,
    '/ranked',
  ),
  Shortcut(
    'fellowships',
    'Partners',
    'Fellowships',
    'The list of fellowships',
    LucideIcons.users2,
    '/fellowships',
  ),
  Shortcut(
    'goals',
    'Church',
    'Goals',
    'This period',
    LucideIcons.target,
    '/goals',
    pastorOnly: true,
  ),
  Shortcut(
    'people',
    'Church',
    'People',
    'Who can sign in',
    LucideIcons.userPlus,
    '/people',
    pastorOnly: true,
  ),
  Shortcut(
    'configuration',
    'Church',
    'Configuration',
    'Arms and periods',
    LucideIcons.sliders,
    '/configuration',
    pastorOnly: true,
  ),
];

/// The most a person can pin.
const maxShortcuts = 4;

const _defaultIds = ['record', 'import', 'queue', 'follow-up'];

/// What this person can pin: staff don't see the pastor-only pages.
List<Shortcut> shortcutsFor({required bool isPastor}) => [
  for (final s in shortcutCatalog)
    if (isPastor || !s.pastorOnly) s,
];

/// This person's pinned shortcuts, in order. Saved on this device, per person
/// and church, the same way the last page they were on is remembered.
final shortcutsProvider = NotifierProvider<ShortcutsNotifier, List<String>>(
  ShortcutsNotifier.new,
);

class ShortcutsNotifier extends Notifier<List<String>> {
  String? _key;

  @override
  List<String> build() {
    final idx = ref.watch(userChurchIndexProvider).valueOrNull;
    if (idx == null) return _defaultIds;
    _key = 'pillr_shortcuts_${idx.uid}_${idx.churchId}';
    Future.microtask(_hydrate);
    return _defaultIds;
  }

  Future<void> _hydrate() async {
    final key = _key;
    if (key == null) return;
    final saved = (await SharedPreferences.getInstance()).getStringList(key);
    if (saved == null) return;
    final known = {for (final s in shortcutCatalog) s.id};
    state = saved.where(known.contains).take(maxShortcuts).toList();
  }

  Future<void> save(List<String> ids) async {
    state = ids.take(maxShortcuts).toList();
    final key = _key;
    if (key == null) return;
    await (await SharedPreferences.getInstance()).setStringList(key, state);
  }
}
