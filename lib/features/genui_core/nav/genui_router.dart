import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/analysis/view/analysis_screen.dart';
import 'package:portfolio_assistant/features/genui_core/models/gen_ui_flow_type.dart';
import 'package:portfolio_assistant/features/investment/models/investment_flow_args.dart';
import 'package:portfolio_assistant/features/investment/view/investment_screen.dart';
import 'package:portfolio_assistant/features/planning/models/planning_flow_args.dart';
import 'package:portfolio_assistant/features/planning/view/planning_screen.dart';

class GenUiRouter {
  static String routeNameFor(GenUiFlowType type) => 'GenUi_${type.name}';

  static String pathFor(GenUiFlowType type) => '/genui/${type.routeSuffix}';

  static InvestmentFlowArgs? _investmentArgs(Object? extra) {
    if (extra is InvestmentFlowArgs) return extra;
    if (extra is String) return InvestmentFlowArgs(initialPrompt: extra);
    return null;
  }

  static PlanningFlowArgs? _planningArgs(Object? extra) {
    if (extra is PlanningFlowArgs) return extra;
    if (extra is String) return PlanningFlowArgs(initialPrompt: extra);
    return null;
  }

  static List<GoRoute> getRoutes() {
    return GenUiFlowType.values.map((type) {
      return GoRoute(
        name: routeNameFor(type),
        path: pathFor(type),
        pageBuilder: (context, state) {
          final extra = state.extra;
          final Widget child = switch (type) {
            GenUiFlowType.analysis => AnalysisScreen(
                initialPrompt: extra is String ? extra : null,
              ),
            GenUiFlowType.invest => InvestmentScreen(
                args: _investmentArgs(extra),
              ),
            GenUiFlowType.plan => PlanningScreen(
                args: _planningArgs(extra),
              ),
          };
          return MaterialPage<void>(
            key: state.pageKey,
            child: child,
            name: routeNameFor(type),
          );
        },
      );
    }).toList();
  }
}
