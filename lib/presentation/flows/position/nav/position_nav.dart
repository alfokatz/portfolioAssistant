import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/presentation/base/navigation/navigation_event.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_router.dart';

class GotoAddPosition extends NavigationEvent {
  final String? ticker;
  final double? quantity;
  final double? purchasePrice;

  GotoAddPosition({
    this.ticker,
    this.quantity,
    this.purchasePrice,
  });

  @override
  void navigate({required BuildContext context}) {
    context.pushNamed(
      PositionRouter.addRouteName,
      extra: {
        if (ticker != null) 'ticker': ticker,
        if (quantity != null) 'quantity': quantity,
        if (purchasePrice != null) 'purchasePrice': purchasePrice,
      },
    );
  }
}

class GotoClosePosition extends NavigationEvent {
  final String positionId;
  final String ticker;
  final double quantity;
  final double avgPurchasePrice;

  GotoClosePosition({
    required this.positionId,
    required this.ticker,
    required this.quantity,
    required this.avgPurchasePrice,
  });

  @override
  void navigate({required BuildContext context}) {
    context.pushNamed(
      PositionRouter.closeRouteName,
      extra: {
        'positionId': positionId,
        'ticker': ticker,
        'quantity': quantity,
        'avgPurchasePrice': avgPurchasePrice,
      },
    );
  }
}

class GotoClosedPositions extends NavigationEvent {
  @override
  void navigate({required BuildContext context}) {
    context.pushNamed(PositionRouter.closedListRouteName);
  }
}

class GotoPositionDetail extends NavigationEvent {
  final String ticker;

  GotoPositionDetail({required this.ticker});

  @override
  void navigate({required BuildContext context}) {
    context.pushNamed(
      PositionRouter.detailRouteName,
      extra: {'ticker': ticker},
    );
  }
}
