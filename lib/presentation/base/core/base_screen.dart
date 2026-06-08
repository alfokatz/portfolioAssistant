import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/navigation/navigator.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_data.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_type.dart';
import 'package:portfolio_assistant/presentation/base/navigation/navigation_event.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

mixin class BaseScreen {
  void subscribeAlert({
    required WidgetRef ref,
    required BuildContext context,
  }) {
    ref.listen<AlertData?>(
      alertProvider,
      (previous, next) {
        if (next == null) return;

        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;

        final backgroundColor = switch (next.alertType) {
          AlertType.success => PortfolioColors.profit,
          AlertType.warning => const Color(0xFFF59E0B),
          AlertType.error => PortfolioColors.loss,
        };

        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: backgroundColor,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              content: Text(
                [
                  if (next.title != null && next.title!.isNotEmpty) next.title,
                  if (next.message != null && next.message!.isNotEmpty)
                    next.message,
                ].join('\n'),
                style: const TextStyle(color: PortfolioColors.textPrimary),
              ),
            ),
          );
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
