import 'package:portfolio_assistant/domain/entities/position_valuation.dart';

sealed class PositionDetailAction {}

class SetLoadingAction extends PositionDetailAction {}

class LoadLotsSuccessAction extends PositionDetailAction {
  LoadLotsSuccessAction({
    required this.lots,
    required this.summary,
  });

  final List<PositionValuation> lots;
  final PositionValuation? summary;
}

class LoadLotsErrorAction extends PositionDetailAction {
  LoadLotsErrorAction(this.message);

  final String message;
}

class RequestCloseLotAction extends PositionDetailAction {
  RequestCloseLotAction(this.lot);

  final PositionValuation lot;
}

class RequestCloseAllAction extends PositionDetailAction {
  RequestCloseAllAction(this.summary);

  final PositionValuation summary;
}

class ClearCloseRequestAction extends PositionDetailAction {}

class SetShouldPopAction extends PositionDetailAction {
  SetShouldPopAction(this.shouldPop);

  final bool shouldPop;
}
