import 'package:portfolio_assistant/domain/entities/position.dart';

class PositionValuation {
  final Position position;
  final double currentPrice;
  final double marketValue;
  final double pnlAbsolute;
  final double pnlPercent;

  const PositionValuation({
    required this.position,
    required this.currentPrice,
    required this.marketValue,
    required this.pnlAbsolute,
    required this.pnlPercent,
  });
}
