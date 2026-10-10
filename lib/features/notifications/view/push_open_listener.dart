import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/etoro/nav/etoro_router.dart';
import 'package:portfolio_assistant/features/notifications/data/notifications_repository.dart';
import 'package:portfolio_assistant/features/notifications/domain/push_route.dart';
import 'package:portfolio_assistant/features/notifications/nav/notifications_router.dart';
import 'package:portfolio_assistant/features/notifications/providers/push_controller.dart';
import 'package:portfolio_assistant/features/weekly_report/nav/weekly_report_router.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_nav.dart';

/// Abre lo que corresponde al tocar una notificación: la que abrió la app
/// desde cerrada y las que se tocan con la app viva. Va dentro del shell
/// (sesión iniciada y onboarding hecho), así el destino siempre existe.
class PushOpenListener extends ConsumerStatefulWidget {
  const PushOpenListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PushOpenListener> createState() => _PushOpenListenerState();
}

class _PushOpenListenerState extends ConsumerState<PushOpenListener> {
  StreamSubscription<PushMessage>? _sub;

  /// La notificación que abrió la app se atiende una vez por proceso: el
  /// shell se vuelve a montar al cerrar e iniciar sesión, y la de Android
  /// (notificación local) se seguiría informando.
  static bool _initialHandled = false;

  @override
  void initState() {
    super.initState();
    final messaging = ref.read(pushMessagingProvider);
    _sub = messaging.onOpened.listen(_open);
    if (!_initialHandled) {
      _initialHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final initial = await messaging.initialMessage();
        if (initial != null && mounted) _open(initial);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _open(PushMessage message) {
    final logId = message.logId;
    if (logId != null) {
      unawaited(
        ref
            .read(notificationsRepositoryProvider)
            .markOpened(logId)
            .catchError((_) {}),
      );
    }
    final route = message.route;
    if (route == null || !mounted) return;
    final holdings =
        ref
            .read(homeProvider)
            .summary
            ?.valuations
            .map((v) => v.position.ticker.toUpperCase())
            .toSet() ??
        const <String>{};
    openPushRoute(context, route, holds: holdings.contains);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Navega a [route]. [holds] dice si el usuario tiene el ticker en cartera
/// (una alerta de un ticker que no tiene abre la lista de alertas).
void openPushRoute(
  BuildContext context,
  PushRoute route, {
  required bool Function(String ticker) holds,
}) {
  switch (route) {
    case PushRouteHome():
      context.goNamed(HomeRouter.homeRouteName);
    case PushRouteWeeklyReport():
      context.pushNamed(WeeklyReportRouter.routeName);
    case PushRouteEtoro():
      context.pushNamed(EtoroRouter.connectionRouteName);
    case PushRouteNotificationSettings():
      context.pushNamed(NotificationsRouter.settingsRouteName);
    case PushRoutePriceAlerts():
      context.pushNamed(NotificationsRouter.alertsRouteName);
    case PushRouteTicker(:final ticker):
      if (holds(ticker.toUpperCase())) {
        GotoPositionDetail(ticker: ticker).navigate(context: context);
      } else {
        context.pushNamed(NotificationsRouter.alertsRouteName);
      }
    case PushRouteAssistant(:final question):
      GotoAssistant(initialQuestion: question).navigate(context: context);
  }
}
