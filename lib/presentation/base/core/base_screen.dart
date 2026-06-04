import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/navigation/navigator.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_data.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/navigation/navigation_event.dart';

mixin class BaseScreen {
  void subscribeAlert({required WidgetRef ref}) {
    ref.listen<AlertData?>(
      alertProvider,
      (previous, next) {
        if (next != null) {
          //todo mostrar alertas
        }
      },
    );
  }

  void subscribeNavigation({
    required WidgetRef ref,
    required BuildContext context,
  }) {
    ref.listen<NavigationEvent?>(
      navigationProvider,
      (previous, next) {
        if (next != null) {
          next.navigate(context: context);
        }
      },
    );
  }

  void runAfterPostFrameCallback(Function function) {
    WidgetsFlutterBinding.ensureInitialized().addPostFrameCallback(
      (_) {
        function.call();
      },
    );
  }
}
