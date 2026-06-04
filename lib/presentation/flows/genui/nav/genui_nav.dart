import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/investment/models/investment_flow_args.dart';
import 'package:portfolio_assistant/features/planning/models/planning_flow_args.dart';
import 'package:portfolio_assistant/features/genui_core/models/gen_ui_flow_type.dart';
import 'package:portfolio_assistant/presentation/base/navigation/navigation_event.dart';
import 'package:portfolio_assistant/presentation/flows/genui/nav/genui_router.dart';

class GotoGenUiFlow extends NavigationEvent {
  final GenUiFlowType flowType;
  final String? initialPrompt;
  final InvestmentFlowArgs? investmentArgs;
  final PlanningFlowArgs? planningArgs;

  GotoGenUiFlow({
    required this.flowType,
    this.initialPrompt,
    this.investmentArgs,
    this.planningArgs,
  });

  @override
  void navigate({required BuildContext context}) {
    final Object? extra = switch (flowType) {
      GenUiFlowType.invest => investmentArgs ??
          (initialPrompt != null
              ? InvestmentFlowArgs(initialPrompt: initialPrompt)
              : null),
      GenUiFlowType.plan => planningArgs ??
          (initialPrompt != null
              ? PlanningFlowArgs(initialPrompt: initialPrompt)
              : null),
      _ => initialPrompt,
    };

    context.pushNamed(
      GenUiRouter.routeNameFor(flowType),
      extra: extra,
    );
  }
}
