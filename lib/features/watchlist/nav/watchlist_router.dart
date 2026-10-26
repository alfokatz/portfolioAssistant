import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/watchlist/view/watchlist_screen.dart';

/// Ruta de nivel superior: se llega desde la Home (debajo de las
/// posiciones).
class WatchlistRouter {
  static const routeName = 'Watchlist';
  static const path = '/watchlist';

  static GoRoute getRoute() => GoRoute(
    name: routeName,
    path: path,
    pageBuilder:
        (context, state) => MaterialPage<void>(
          key: state.pageKey,
          name: routeName,
          child: const WatchlistScreen(),
        ),
  );
}
