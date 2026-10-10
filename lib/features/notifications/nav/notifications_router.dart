import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/notifications/view/notification_settings_screen.dart';
import 'package:portfolio_assistant/features/notifications/view/price_alerts_screen.dart';

/// Rutas de nivel superior (fuera del shell de tabs): se llega desde
/// Ajustes, desde el detalle de una posición y al tocar una notificación.
class NotificationsRouter {
  static const settingsRouteName = 'NotificationSettings';
  static const settingsPath = '/notifications';
  static const alertsRouteName = 'PriceAlerts';
  static const alertsPath = '/alerts';

  static List<GoRoute> getRoutes() => [
    GoRoute(
      name: settingsRouteName,
      path: settingsPath,
      pageBuilder:
          (context, state) => MaterialPage<void>(
            key: state.pageKey,
            name: settingsRouteName,
            child: const NotificationSettingsScreen(),
          ),
    ),
    GoRoute(
      name: alertsRouteName,
      path: alertsPath,
      pageBuilder:
          (context, state) => MaterialPage<void>(
            key: state.pageKey,
            name: alertsRouteName,
            child: const PriceAlertsScreen(),
          ),
    ),
  ];
}
