import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/snaptrade/view/snaptrade_screen.dart';

/// Ruta de nivel superior: se llega desde Ajustes → Cuentas conectadas.
class SnaptradeRouter {
  static const routeName = 'Snaptrade';
  static const path = '/snaptrade';

  static GoRoute getRoute() => GoRoute(
    name: routeName,
    path: path,
    pageBuilder:
        (context, state) => MaterialPage<void>(
          key: state.pageKey,
          name: routeName,
          child: const SnaptradeScreen(),
        ),
  );
}
