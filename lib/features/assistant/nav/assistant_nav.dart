import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_router.dart';
import 'package:portfolio_assistant/presentation/base/navigation/navigation_event.dart';

class GotoAssistant extends NavigationEvent {
  GotoAssistant({this.initialQuestion});

  final String? initialQuestion;

  @override
  void navigate({required BuildContext context}) {
    context.goNamed(AssistantRouter.routeName, extra: initialQuestion);
  }
}
