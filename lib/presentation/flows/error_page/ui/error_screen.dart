import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter_riverpod/src/consumer.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateless_screen.dart';

class ErrorScreen extends BaseStatelessScreen {
  final Exception? error;
  late String message;

  ErrorScreen({
    this.error,
  }) {
    if (error != null) {
      message = error.toString();
    } else {
      message = 'Error';
    }
  }

  @override
  Widget buildView(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Text(message),
      ),
    );
  }
}
