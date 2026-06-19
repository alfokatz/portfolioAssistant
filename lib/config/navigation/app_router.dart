import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/navigation/go_router_refresh.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/presentation/flows/auth/nav/auth_router.dart';
import 'package:portfolio_assistant/presentation/flows/error_page/nav/error_router.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_router.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/nav/onboarding_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_router.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';

class AppRouter {
  final Ref ref;

  AppRouter({required this.ref});

  GoRouter getRouter() {
    final refresh = GoRouterRefresh(
      ref.read(supabaseClientProvider).auth.onAuthStateChange,
    );
    ref.onDispose(refresh.dispose);

    return GoRouter(
      debugLogDiagnostics: true,
      refreshListenable: refresh,
      redirect: (context, state) {
        final isAuthenticated = ref.read(isAuthenticatedProvider);
        final location = state.matchedLocation;
        final isLoginRoute = location == AuthRouter.loginPath;
        final isOnboardingRoute = location == OnboardingRouter.path;
        final onboardingDone =
            ref.read(preferenceManagerProvider).hasCompletedOnboarding();

        if (!isAuthenticated) {
          if (!isLoginRoute) return AuthRouter.loginPath;
          return null;
        }

        if (isLoginRoute) {
          if (!onboardingDone) return OnboardingRouter.path;
          return state.namedLocation(HomeRouter.homeRouteName);
        }

        if (!onboardingDone && !isOnboardingRoute) {
          return OnboardingRouter.path;
        }

        if (onboardingDone && isOnboardingRoute) {
          return state.namedLocation(HomeRouter.homeRouteName);
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          redirect: (context, state) {
            final isAuthenticated = ref.read(isAuthenticatedProvider);
            if (!isAuthenticated) return AuthRouter.loginPath;
            final onboardingDone =
                ref.read(preferenceManagerProvider).hasCompletedOnboarding();
            if (!onboardingDone) return OnboardingRouter.path;
            return state.namedLocation(HomeRouter.homeRouteName);
          },
        ),
        AuthRouter.getRoute(),
        OnboardingRouter.getRoute(),
        HomeRouter.getRoute(),
        ...PositionRouter.getRoutes(),
        AssistantRouter.getRoute(),
        AssistantRouter.getLegacyRedirect(),
      ],
      errorPageBuilder: (context, state) =>
          ErrorNav.getErrorPage(exception: state.error),
    );
  }
}

final appRouterProvider = Provider<GoRouter>(
  (ref) => AppRouter(ref: ref).getRouter(),
);
