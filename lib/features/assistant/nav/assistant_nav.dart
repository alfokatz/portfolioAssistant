import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode_codec.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_router.dart';
import 'package:portfolio_assistant/presentation/base/navigation/navigation_event.dart';

class GotoAssistant extends NavigationEvent {
  GotoAssistant({this.mode = AssistantMode.portfolio, this.initialQuestion});

  final AssistantMode mode;
  final String? initialQuestion;

  @override
  void navigate({required BuildContext context}) {
    context.pushNamed(
      AssistantRouter.routeName,
      queryParameters:
          mode == AssistantMode.portfolio ? {} : {'mode': mode.queryValue},
      extra: initialQuestion,
    );
  }
}
