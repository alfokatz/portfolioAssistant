import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/etoro/view/etoro_connection_screen.dart';
import 'package:portfolio_assistant/features/etoro/view/etoro_import_result_screen.dart';

/// Rutas de nivel superior (fuera del shell de tabs), como el perfil de
/// inversor: se llega desde Ajustes, desde la Home vacía y desde el
/// onboarding, y "atrás" vuelve a donde estaba el usuario.
class EtoroRouter {
  static const connectionRouteName = 'EtoroConnection';
  static const connectionPath = '/etoro';
  static const resultRouteName = 'EtoroImportResult';
  static const resultPath = '/etoro/result';

  /// `?sync=failed`: la cuenta quedó conectada pero la primera importación
  /// falló (se reintenta sola).
  static const syncFailedParam = 'sync';

  static List<GoRoute> getRoutes() => [
    GoRoute(
      name: connectionRouteName,
      path: connectionPath,
      pageBuilder:
          (context, state) => MaterialPage<void>(
            key: state.pageKey,
            name: connectionRouteName,
            child: const EtoroConnectionScreen(),
          ),
    ),
    GoRoute(
      name: resultRouteName,
      path: resultPath,
      pageBuilder:
          (context, state) => MaterialPage<void>(
            key: state.pageKey,
            name: resultRouteName,
            child: EtoroImportResultScreen(
              syncFailed:
                  state.uri.queryParameters[syncFailedParam] == 'failed',
            ),
          ),
    ),
  ];
}
