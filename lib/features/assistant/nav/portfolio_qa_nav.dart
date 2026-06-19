import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/presentation/base/navigation/navigation_event.dart';

@Deprecated('Use GotoAssistant instead')
class GotoPortfolioQa extends NavigationEvent {
  GotoPortfolioQa({this.initialQuestion});

  final String? initialQuestion;

  @override
  void navigate({required BuildContext context}) {
    GotoAssistant(initialQuestion: initialQuestion).navigate(context: context);
  }
}
