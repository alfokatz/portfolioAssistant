import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/presentation/base/navigation/navigation_event.dart';
import 'package:portfolio_assistant/presentation/flows/settings/nav/settings_router.dart';

class GotoSettings extends NavigationEvent {
  @override
  void navigate({required BuildContext context}) {
    context.pushNamed(SettingsRouter.settingsRouteName);
  }
}
