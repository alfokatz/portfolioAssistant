import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/settings_screen.dart';

class SettingsRouter {
  static const String settingsRouteName = 'Settings';

  /// Ajustes como pantalla apilada (con Noticias prendida no es pestaña).
  static const String pushedRouteName = 'SettingsPushed';

  static GoRoute getRoute() {
    return GoRoute(
      name: settingsRouteName,
      path: '/settings',
      pageBuilder:
          (context, state) => MaterialPage<void>(
            key: state.pageKey,
            name: settingsRouteName,
            child: const SettingsScreen(),
          ),
    );
  }

  static GoRoute getPushedRoute() {
    return GoRoute(
      name: pushedRouteName,
      path: '/profile-settings',
      pageBuilder:
          (context, state) => MaterialPage<void>(
            key: state.pageKey,
            name: pushedRouteName,
            child: const SettingsScreen(pushed: true),
          ),
    );
  }

  /// Abre Ajustes: como pestaña (`goNamed`) con la barra de siempre, o
  /// apilada (`pushNamed`) cuando la rama de la barra está oculta.
  static void open(BuildContext context) {
    final pushed = ProviderScope.containerOf(
      context,
    ).read(newsFeedAvailableProvider);
    if (pushed) {
      context.pushNamed(pushedRouteName);
    } else {
      context.goNamed(settingsRouteName);
    }
  }
}
