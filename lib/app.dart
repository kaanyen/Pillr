import 'package:flutter/material.dart';
import 'package:the_pillr/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/extensions/async_value_ext.dart';
import 'core/providers/locale_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/color_utils.dart';
import 'features/church/providers/church_settings_providers.dart';

class PillrApp extends ConsumerWidget {
  const PillrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(churchSettingsProvider).valueOrNull;
    final seed = parseHexColor(settings?.primaryColorHex);
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(seedColor: seed),
      routerConfig: appRouter,
    );
  }
}
