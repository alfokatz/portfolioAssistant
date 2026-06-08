import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/login_screen.dart';

class AuthRouter {
  static const String loginRouteName = 'Login';
  static const String loginPath = '/login';

  static GoRoute getRoute() {
    return GoRoute(
      name: loginRouteName,
      path: loginPath,
      pageBuilder: (context, state) => MaterialPage<void>(
        key: state.pageKey,
        child: const LoginScreen(),
        name: loginRouteName,
      ),
    );
  }
}
