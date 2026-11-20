import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_router.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/presentation/base/navigation/navigation_event.dart';

class GotoAssistant extends NavigationEvent {
  GotoAssistant({this.initialQuestion, this.screen, this.origin});

  final String? initialQuestion;

  /// Lo que el usuario estaba mirando: viaja con la pregunta en el brief.
  final PortyScreenContext? screen;

  /// De dónde salió la pregunta (el widget); solo cuenta con [initialQuestion].
  final AssistantQuestionOrigin? origin;

  @override
  void navigate({required BuildContext context}) {
    final question = initialQuestion;
    context.goNamed(
      AssistantRouter.routeName,
      extra:
          question == null
              ? null
              : AssistantQuestionRequest(
                question,
                screen: screen,
                origin: origin,
              ),
    );
  }
}
