import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/news_feed/view/news_topic_screen.dart';

/// `/news/topic`, con `extra: topicId` (un id del catálogo de temas).
class NewsTopicRouter {
  static const String routeName = 'NewsTopic';
  static const String path = '/news/topic';

  /// Los ids del catálogo son `^[a-z0-9_]{2,40}$`.
  static final _id = RegExp(r'^[a-z0-9_]{2,40}$');

  static GoRoute getRoute() {
    return GoRoute(
      name: routeName,
      path: path,
      pageBuilder: (context, state) {
        final extra = state.extra;
        final id = extra is String && _id.hasMatch(extra) ? extra : null;
        return MaterialPage<void>(
          key: state.pageKey,
          child:
              id == null
                  ? const Scaffold(body: SizedBox.shrink())
                  : NewsTopicScreen(topicId: id),
          name: routeName,
        );
      },
    );
  }
}
