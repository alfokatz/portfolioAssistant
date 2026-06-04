import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/home_screen.dart';
import 'package:portfolio_assistant/presentation/flows/settings/nav/settings_router.dart';

class HomeRouter {
  static const String homeRouteName = 'Home';

  static GoRoute getRoute() {
    return GoRoute(
      name: homeRouteName,
      path: '/Home',
      pageBuilder:
          (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: HomeScreen(),
            name: homeRouteName,
          ),
      routes: [SettingsRouter.getRoute()],
    );
  }
}
