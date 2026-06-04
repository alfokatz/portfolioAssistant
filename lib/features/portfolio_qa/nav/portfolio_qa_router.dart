import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/portfolio_qa/view/portfolio_qa_screen.dart';

class PortfolioQaRouter {
  static const routeName = 'PortfolioQa';
  static const path = '/portfolio-qa';

  static GoRoute getRoute() {
    return GoRoute(
      name: routeName,
      path: path,
      pageBuilder: (context, state) {
        final extra = state.extra;
        return MaterialPage<void>(
          key: state.pageKey,
          name: routeName,
          child: PortfolioQaScreen(
            initialQuestion: extra is String ? extra : null,
          ),
        );
      },
    );
  }
}
