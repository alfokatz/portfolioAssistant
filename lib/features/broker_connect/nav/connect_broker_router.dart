import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/broker_connect/view/connect_broker_screen.dart';

/// "Conectá tu bróker": se llega desde el onboarding, Ajustes y la Home.
class ConnectBrokerRouter {
  static const routeName = 'ConnectBroker';
  static const path = '/connect-broker';

  static GoRoute getRoute() => GoRoute(
    name: routeName,
    path: path,
    pageBuilder:
        (context, state) => MaterialPage<void>(
          key: state.pageKey,
          name: routeName,
          child: const ConnectBrokerScreen(),
        ),
  );
}
