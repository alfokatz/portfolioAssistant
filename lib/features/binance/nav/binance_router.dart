import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/binance/view/binance_screen.dart';

/// Ruta de nivel superior: se llega desde Ajustes → Cuentas conectadas.
class BinanceRouter {
  static const routeName = 'Binance';
  static const path = '/binance';

  static GoRoute getRoute() => GoRoute(
    name: routeName,
    path: path,
    pageBuilder:
        (context, state) => MaterialPage<void>(
          key: state.pageKey,
          name: routeName,
          child: const BinanceScreen(),
        ),
  );
}
