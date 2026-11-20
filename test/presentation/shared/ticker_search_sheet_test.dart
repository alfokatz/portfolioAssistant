import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/symbol_search_result.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/repositories/symbol_search_repository.dart';
import 'package:portfolio_assistant/domain/use_cases/get_current_price_use_case.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/ticker_search_sheet.dart';

class _Search implements SymbolSearchRepository {
  _Search({this.fail = false});

  final bool fail;

  @override
  Future<Either<HttpError, List<SymbolSearchResult>>> search(String q) async {
    if (fail) return Left(HttpError(code: 'network_error'));
    if (q.toLowerCase().startsWith('app')) {
      return const Right([
        SymbolSearchResult(
          symbol: 'AAPL',
          description: 'APPLE INC',
          type: 'Common Stock',
        ),
        SymbolSearchResult(
          symbol: 'APLE',
          description: 'APPLE HOSPITALITY REIT INC',
          type: 'REIT',
        ),
      ]);
    }
    return const Right([]);
  }
}

class _Quotes implements QuoteRepository {
  _Quotes(this.known);

  final Set<String> known;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async =>
      known.contains(ticker)
          ? const Right(10.0)
          : Left(HttpError(code: 'quote_error'));
}

void main() {
  late String? picked;

  Future<void> open(
    WidgetTester tester, {
    SymbolSearchRepository? search,
    Set<String> known = const {},
    Set<String> existing = const {},
  }) async {
    picked = null;
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = ProviderContainer().read(themeDataLightProvider);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          symbolSearchRepositoryProvider.overrideWithValue(search ?? _Search()),
          getCurrentPriceUseCaseProvider.overrideWithValue(
            GetCurrentPriceUseCase(quoteRepository: _Quotes(known)),
          ),
        ],
        child: MaterialApp(
          theme: theme,
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      picked = await TickerSearchSheet.show(
                        context,
                        title: 'Sumar',
                        existing: existing,
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('busca por nombre y elige un resultado', (tester) async {
    await open(tester, existing: {'APLE'});
    await type(tester, 'apple');
    expect(find.text('ticker_search_results'), findsOneWidget);
    expect(find.text('Apple Inc · ticker_search_kind_stock'), findsOneWidget);
    // Lo que ya está se marca y no se elige.
    expect(find.text('ticker_search_taken'), findsOneWidget);
    await tester.tap(find.text('AAPL'));
    await tester.pump(const Duration(seconds: 1));
    expect(picked, 'AAPL');
  });

  testWidgets('un ticker escrito a mano se verifica con la cotización', (
    tester,
  ) async {
    await open(tester, known: {'GGAL.BA'});
    await type(tester, 'ggal.ba');
    expect(find.text('ticker_search_empty'), findsOneWidget);
    await tester.tap(find.text('ticker_search_use_typed'));
    await tester.pump(const Duration(seconds: 1));
    expect(picked, 'GGAL.BA');
  });

  testWidgets('sin cotización, Porty dice qué revisar', (tester) async {
    await open(tester);
    await type(tester, 'ggal');
    await tester.tap(find.text('ticker_search_use_typed'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('ticker_search_not_found'), findsOneWidget);
    expect(picked, isNull);
  });

  testWidgets('si la búsqueda falla, igual se puede usar lo escrito', (
    tester,
  ) async {
    await open(tester, search: _Search(fail: true), known: {'VOO'});
    await type(tester, 'voo');
    expect(find.text('ticker_search_failed'), findsOneWidget);
    await tester.tap(find.text('ticker_search_use_typed'));
    await tester.pump(const Duration(seconds: 1));
    expect(picked, 'VOO');
  });
}
