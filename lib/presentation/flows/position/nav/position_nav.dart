import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/presentation/base/navigation/navigation_event.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/position_detail_state.dart';

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

  /// Datos que ya tiene la pantalla de origen (ver [PositionDetailSeed]).
  final PositionDetailSeed? seed;

  GotoPositionDetail({required this.ticker, this.seed});

  @override
  void navigate({required BuildContext context}) {
    context.pushNamed(
      PositionRouter.detailRouteName,
      extra: {'ticker': ticker, if (seed != null) 'seed': seed},
    );
  }
}

/// El detalle de una venta. Con [seed] (la venta ya cargada) se ve completo
/// desde el primer frame; sin él, lo busca por [id].
class GotoClosedPositionDetail extends NavigationEvent {
  GotoClosedPositionDetail({
    required this.id,
    required this.ticker,
    this.seed,
  });

  GotoClosedPositionDetail.of(ClosedPosition sale)
    : id = sale.id,
      ticker = sale.ticker,
      seed = sale;

  final String id;
  final String ticker;
  final ClosedPosition? seed;

  @override
  void navigate({required BuildContext context}) {
    context.pushNamed(
      PositionRouter.closedDetailRouteName,
      extra: {'id': id, 'ticker': ticker, if (seed != null) 'seed': seed},
    );
  }
}
