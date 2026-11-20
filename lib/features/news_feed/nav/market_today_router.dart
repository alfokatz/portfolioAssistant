import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/news_feed/view/market_today_screen.dart';

/// "Mercado hoy" con ruta propia (`/market-today`).
class MarketTodayRouter {
  static const String routeName = 'MarketToday';
  static const String path = '/market-today';

  static GoRoute getRoute() {
    return GoRoute(
      name: routeName,
      path: path,
      pageBuilder:
          (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const MarketTodayScreen(),
            name: routeName,
          ),
    );
  }
}
