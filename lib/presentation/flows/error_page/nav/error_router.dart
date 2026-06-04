import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/presentation/flows/error_page/ui/error_screen.dart';

class ErrorNav {

  static MaterialPage getErrorPage({required GoException? exception}) {
    return MaterialPage<void>(
      child: ErrorScreen(
        error: exception,
      ),
    );
  }
}
