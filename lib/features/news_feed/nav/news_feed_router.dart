import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/news_feed/view/news_feed_screen.dart';

/// `/news`, con `extra: {tab, source}` (`tab`: `mine` | `topics` | `market`;
/// `source`: `brief` | `home` | `push`). Sin extra, abre "Lo tuyo" desde la
/// Home.
class NewsFeedRouter {
  static const String routeName = 'NewsFeed';
  static const String path = '/news';

  static Map<String, String> args({
    String tab = 'mine',
    String source = 'home',
  }) => {'tab': tab, 'source': source};

  static GoRoute getRoute() {
    return GoRoute(
      name: routeName,
      path: path,
      pageBuilder: (context, state) {
        final extra = state.extra;
        final map = extra is Map ? extra : const {};
        return MaterialPage<void>(
          key: state.pageKey,
          child: NewsFeedScreen(
            tab: map['tab'] is String ? map['tab'] as String : 'mine',
            source: map['source'] is String ? map['source'] as String : 'home',
          ),
          name: routeName,
        );
      },
    );
  }
}
