import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/add_position_screen.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/close_position_screen.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/closed_positions_screen.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/position_detail_screen.dart';

class PositionRouter {
  static const String addRouteName = 'AddPosition';
  static const String addPath = '/position/add';
  static const String closeRouteName = 'ClosePosition';
  static const String closePath = '/position/close';
  static const String detailRouteName = 'PositionDetail';
  static const String detailPath = '/position/detail';
  static const String closedListRouteName = 'ClosedPositions';
  static const String closedListPath = '/position/closed';

  static List<GoRoute> getRoutes() {
    return [
      GoRoute(
        name: addRouteName,
        path: addPath,
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return MaterialPage<void>(
            key: state.pageKey,
            child: AddPositionScreen(
              prefilledTicker: extra?['ticker'] as String?,
              prefilledQuantity: extra?['quantity'] as double?,
              prefilledPrice: extra?['purchasePrice'] as double?,
            ),
            name: addRouteName,
          );
        },
      ),
      GoRoute(
        name: closeRouteName,
        path: closePath,
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return MaterialPage<void>(
            key: state.pageKey,
            child: ClosePositionScreen(
              positionId: extra?['positionId'] as String? ?? '',
              ticker: extra?['ticker'] as String? ?? '',
              quantity: (extra?['quantity'] as num?)?.toDouble() ?? 0,
              avgPurchasePrice:
                  (extra?['avgPurchasePrice'] as num?)?.toDouble() ?? 0,
            ),
            name: closeRouteName,
          );
        },
      ),
      GoRoute(
        name: detailRouteName,
        path: detailPath,
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return MaterialPage<void>(
            key: state.pageKey,
            child: PositionDetailScreen(
              ticker: extra?['ticker'] as String? ?? '',
            ),
            name: detailRouteName,
          );
        },
      ),
      GoRoute(
        name: closedListRouteName,
        path: closedListPath,
        pageBuilder: (context, state) => MaterialPage<void>(
          key: state.pageKey,
          child: const ClosedPositionsScreen(),
          name: closedListRouteName,
        ),
      ),
    ];
  }
}
