import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/goals/view/goal_detail_screen.dart';
import 'package:portfolio_assistant/features/goals/view/goals_screen.dart';

/// La pestaña Metas (rama del shell) y el detalle de una meta (ruta de
/// nivel superior: se empuja desde la pestaña y desde el chat).
class GoalsRouter {
  static const routeName = 'Goals';
  static const path = '/goals';
  static const detailRouteName = 'GoalDetail';
  static const detailPath = '/goal/:id';

  static GoRoute getRoute() => GoRoute(
    name: routeName,
    path: path,
    pageBuilder:
        (context, state) => MaterialPage<void>(
          key: state.pageKey,
          name: routeName,
          child: const GoalsScreen(),
        ),
  );

  static GoRoute getDetailRoute() => GoRoute(
    name: detailRouteName,
    path: detailPath,
    pageBuilder:
        (context, state) => MaterialPage<void>(
          key: state.pageKey,
          name: detailRouteName,
          child: GoalDetailScreen(goalId: state.pathParameters['id']!),
        ),
  );

  static void openDetail(BuildContext context, String goalId) =>
      context.pushNamed(detailRouteName, pathParameters: {'id': goalId});
}
