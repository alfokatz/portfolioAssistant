import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/use_cases/delete_positions_by_ticker_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_benchmark_comparison_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_history_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_summary_use_case.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

import 'home_loading_test.dart' show sampleSummary;

/// Cada llamada queda pendiente hasta que el test la suelta, en el orden
/// que quiera.
class _HeldSummary extends _Unused implements GetPortfolioSummaryUseCase {
  final calls = <Completer<PortfolioSummary>>[];

  @override
  Future<Either<HttpError, PortfolioSummary>> call({void params}) {
    final c = Completer<PortfolioSummary>();
    calls.add(c);
    return c.future.then(Right.new);
  }
}

class _History extends _Unused implements GetPortfolioHistoryUseCase {
  @override
  Future<Either<HttpError, List<PortfolioHistoryPoint>>> call({
    void params,
  }) async => const Right([]);
}

class _Benchmark extends _Unused implements GetBenchmarkComparisonUseCase {
  @override
  Future<Either<HttpError, List<BenchmarkPoint>>> call({void params}) async =>
      const Right([]);
}

class _Closed extends _Unused implements GetClosedPositionsUseCase {
  @override
  Future<Either<HttpError, List<ClosedPosition>>> call({void params}) async =>
      const Right([]);
}

class _Delete extends _Unused implements DeletePositionsByTickerUseCase {}

class _Unused {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  test('an older refresh that finishes last does not overwrite the newer '
      'portfolio, and waits for it before returning', () async {
    final summary = _HeldSummary();
    final container = ProviderContainer(
      overrides: [
        homeProvider.overrideWith(
          (ref) => HomeProvider(
            ref: ref,
            getPortfolioSummaryUseCase: summary,
            getPortfolioHistoryUseCase: _History(),
            getBenchmarkComparisonUseCase: _Benchmark(),
            deletePositionsByTickerUseCase: _Delete(),
            getClosedPositionsUseCase: _Closed(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final home = container.read(homeProvider.notifier);

    // Antes de importar (1) y después de que un bróker importó (2).
    final before = home.refresh();
    final after = home.refresh();
    var beforeDone = false;
    unawaited(before.then((_) => beforeDone = true));

    summary.calls[0].complete(sampleSummary(150));
    await pumpEventQueue();
    // La vieja terminó primero pero no escribe, y espera a la nueva.
    expect(container.read(homeProvider).summary, isNull);
    expect(beforeDone, isFalse);

    summary.calls[1].complete(sampleSummary(300));
    await after;
    await before;
    expect(container.read(homeProvider).summary!.totalValue, 600);
    expect(container.read(homeProvider).loading, isFalse);
  });

  test('the newer refresh finishing first is not overwritten later', () async {
    final summary = _HeldSummary();
    final container = ProviderContainer(
      overrides: [
        homeProvider.overrideWith(
          (ref) => HomeProvider(
            ref: ref,
            getPortfolioSummaryUseCase: summary,
            getPortfolioHistoryUseCase: _History(),
            getBenchmarkComparisonUseCase: _Benchmark(),
            deletePositionsByTickerUseCase: _Delete(),
            getClosedPositionsUseCase: _Closed(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final home = container.read(homeProvider.notifier);

    final before = home.refresh();
    final after = home.refresh();
    summary.calls[1].complete(sampleSummary(300));
    await after;
    summary.calls[0].complete(sampleSummary(150));
    await before;
    expect(container.read(homeProvider).summary!.totalValue, 600);
  });
}
