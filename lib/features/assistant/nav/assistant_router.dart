import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
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
        final extra = state.extra;
        return MaterialPage<void>(
          key: state.pageKey,
          name: routeName,
          child: AssistantScreen(
            question: switch (extra) {
              AssistantQuestionRequest() => extra,
              String() => AssistantQuestionRequest(extra),
              _ => null,
            },
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
