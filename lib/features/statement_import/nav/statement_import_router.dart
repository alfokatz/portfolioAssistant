import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/statement_import/view/statement_import_screen.dart';

/// Ruta de nivel superior (fuera del shell de tabs): se llega desde la Home
/// vacía y desde Ajustes, y "atrás" vuelve a donde estaba el usuario.
class StatementImportRouter {
  static const routeName = 'StatementImport';
  static const path = '/import';

  static GoRoute getRoute() => GoRoute(
    name: routeName,
    path: path,
    pageBuilder:
        (context, state) => MaterialPage<void>(
          key: state.pageKey,
          name: routeName,
          child: const StatementImportScreen(),
        ),
  );
}
