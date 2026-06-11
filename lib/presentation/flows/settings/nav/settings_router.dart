import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/settings_screen.dart';

class SettingsRouter {
  static const String settingsRouteName = 'Settings';

  static GoRoute getRoute() {
    return GoRoute(
      name: settingsRouteName,
      path: 'Settings',
      pageBuilder: (context, state) => MaterialPage<void>(
        key: state.pageKey,
        child: const SettingsScreen(),
      ),
    );
  }
}
