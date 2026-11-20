import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_data.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_type.dart';

class AlertProvider extends StateNotifier<AlertData?> {
  AlertProvider() : super(null);

  void showSuccess({String? title, String? message}) {
    state = AlertData(
      alertType: AlertType.success,
      title: title,
      message: message,
    );
    _hide();
  }

  void showWarning({String? title, String? message}) {
    state = AlertData(
      alertType: AlertType.warning,
      title: title,
      message: message,
    );
    _hide();
  }

  void showError({String? title, String? message}) {
    state = AlertData(
      alertType: AlertType.error,
      title: title,
      message: message,
    );
    _hide();
  }

  void _hide() {
    Future.delayed(
      Duration(milliseconds: 350),
      () {
        // El provider es autoDispose: si nadie lo escucha ya se descartó, y
        // tocar el estado después tira (visto en tests, intermitente).
        if (mounted) state = null;
      },
    );
  }
}

final alertProvider =
    StateNotifierProvider.autoDispose<AlertProvider, AlertData?>(
  (ref) => AlertProvider(),
);
