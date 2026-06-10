import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/assistant/nav/portfolio_qa_router.dart';
import 'package:portfolio_assistant/presentation/base/navigation/navigation_event.dart';

class GotoPortfolioQa extends NavigationEvent {
  GotoPortfolioQa({this.initialQuestion});

  final String? initialQuestion;

  @override
  void navigate({required BuildContext context}) {
    context.pushNamed(
      PortfolioQaRouter.routeName,
      extra: initialQuestion,
    );
  }
}
