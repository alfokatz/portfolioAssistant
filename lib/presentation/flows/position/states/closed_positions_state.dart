import 'package:portfolio_assistant/domain/entities/closed_position.dart';

class ClosedPositionsState {
  final List<ClosedPosition> positions;
  final bool isLoading;

  const ClosedPositionsState({
    this.positions = const [],
    this.isLoading = true,
  });

  ClosedPositionsState copyWith({
    List<ClosedPosition>? positions,
    bool? isLoading,
  }) {
    return ClosedPositionsState(
      positions: positions ?? this.positions,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
