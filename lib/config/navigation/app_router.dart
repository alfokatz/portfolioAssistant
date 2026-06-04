import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/flows/error_page/nav/error_router.dart';
import 'package:portfolio_assistant/features/portfolio_qa/nav/portfolio_qa_router.dart';
import 'package:portfolio_assistant/presentation/flows/genui/nav/genui_router.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_router.dart';

class AppRouter {
  final Ref ref;

  AppRouter({required this.ref});

  GoRouter getRouter() => GoRouter(
        debugLogDiagnostics: true,
        routes: [
          GoRoute(
            path: '/',
            redirect: (context, state) =>
                state.namedLocation(HomeRouter.homeRouteName),
          ),
          HomeRouter.getRoute(),
          ...PositionRouter.getRoutes(),
          PortfolioQaRouter.getRoute(),
          ...GenUiRouter.getRoutes(),
        ],
        errorPageBuilder: (context, state) =>
            ErrorNav.getErrorPage(exception: state.error),
      );
}

final appRouterProvider = Provider((ref) => AppRouter(ref: ref));
