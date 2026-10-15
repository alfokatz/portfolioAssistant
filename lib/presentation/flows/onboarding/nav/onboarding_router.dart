import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/presentation/base/theme/fade_through_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/onboarding_screen.dart';

class OnboardingRouter {
  static const String routeName = 'Onboarding';
  static const String path = '/onboarding';

  static GoRoute getRoute() {
    return GoRoute(
      name: routeName,
      path: path,
      pageBuilder: (context, state) => FadeThroughPage<void>(
        key: state.pageKey,
        child: const OnboardingScreen(),
        name: routeName,
      ),
    );
  }
}
