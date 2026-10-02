import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/presentation/base/theme/fade_through_page.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/login_screen.dart';

class AuthRouter {
  static const String loginRouteName = 'Login';
  static const String loginPath = '/login';

  static GoRoute getRoute() {
    return GoRoute(
      name: loginRouteName,
      path: loginPath,
      pageBuilder: (context, state) => FadeThroughPage<void>(
        key: state.pageKey,
        child: const LoginScreen(),
        name: loginRouteName,
      ),
    );
  }
}
