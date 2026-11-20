import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/news_preferences/view/news_preferences_screen.dart';

/// Ajustes → Noticias (`/settings/news`): temas y medios.
class NewsPreferencesRouter {
  static const String routeName = 'NewsPreferences';
  static const String path = '/settings/news';

  static GoRoute getRoute() {
    return GoRoute(
      name: routeName,
      path: path,
      pageBuilder:
          (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const NewsPreferencesScreen(),
            name: routeName,
          ),
    );
  }
}
