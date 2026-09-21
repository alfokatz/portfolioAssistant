import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_router.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/settings/nav/settings_router.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_bottom_nav_bar.dart';

/// Shared bottom-nav-bar navigation used by every top-level tab (Home,
/// Assistant, Settings). Uses `go` instead of `push` so switching tabs
/// replaces the current one rather than stacking screens on top of it.
void goToAppTab(BuildContext context, AppNavDestination destination) {
  switch (destination) {
    case AppNavDestination.home:
      context.goNamed(HomeRouter.homeRouteName);
    case AppNavDestination.assistant:
      context.goNamed(AssistantRouter.routeName);
    case AppNavDestination.settings:
      context.goNamed(SettingsRouter.settingsRouteName);
  }
}
