import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/closed_positions_state.dart';

class ClosedPositionsProvider extends StateNotifier<ClosedPositionsState> {
  ClosedPositionsProvider({
    required this.getClosedPositionsUseCase,
  }) : super(const ClosedPositionsState());

  final GetClosedPositionsUseCase getClosedPositionsUseCase;

  Future<void> load() async {
    state = state.copyWith(isLoading: true);

    final result = await getClosedPositionsUseCase.call();
    state = state.copyWith(
      isLoading: false,
      positions: result.fold((_) => [], (list) => list),
    );
  }
}

final closedPositionsProvider =
    StateNotifierProvider.autoDispose<ClosedPositionsProvider, ClosedPositionsState>(
  (ref) => ClosedPositionsProvider(
    getClosedPositionsUseCase: ref.watch(getClosedPositionsUseCaseProvider),
  ),
);
