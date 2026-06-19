import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode_codec.dart';
import 'package:portfolio_assistant/features/assistant/view/assistant_screen.dart';

class AssistantRouter {
  static const routeName = 'Assistant';
  static const path = '/assistant';
  static const legacyPath = '/portfolio-qa';

  static GoRoute getRoute() {
    return GoRoute(
      name: routeName,
      path: path,
      pageBuilder: (context, state) {
        final mode = AssistantModeCodec.fromQuery(
          state.uri.queryParameters['mode'],
        );
        final extra = state.extra;
        return MaterialPage<void>(
          key: state.pageKey,
          name: routeName,
          child: AssistantScreen(
            initialMode: mode,
            initialQuestion: extra is String ? extra : null,
          ),
        );
      },
    );
  }

  static GoRoute getLegacyRedirect() {
    return GoRoute(
      path: legacyPath,
      redirect: (context, state) {
        final q = state.uri.query;
        return q.isEmpty ? path : '$path?$q';
      },
    );
  }
}
