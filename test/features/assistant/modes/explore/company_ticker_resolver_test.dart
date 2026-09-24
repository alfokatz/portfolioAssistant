import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/symbol_search_result.dart';
import 'package:portfolio_assistant/domain/repositories/symbol_search_repository.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/company_ticker_resolver.dart';

class _FakeSymbolSearchRepository implements SymbolSearchRepository {
  _FakeSymbolSearchRepository(this.onSearch);

  final Future<Either<HttpError, List<SymbolSearchResult>>> Function(
    String query,
  )
  onSearch;

  @override
  Future<Either<HttpError, List<SymbolSearchResult>>> search(String query) {
    return onSearch(query);
  }
}

void main() {
  group('CompanyTickerResolver', () {
    test('resolves a single Common Stock match', () async {
      final resolver = CompanyTickerResolver(
        repository: _FakeSymbolSearchRepository(
          (_) async => const Right([
            SymbolSearchResult(
              symbol: 'AAPL',
              description: 'APPLE INC',
              type: 'Common Stock',
            ),
          ]),
        ),
      );

      final resolution = await resolver.resolve('Apple');

      expect(resolution.ticker, 'AAPL');
      expect(resolution.matches, isNull);
    });

    test(
      'is ambiguous when 2+ primary Common Stock matches exist',
      () async {
        final resolver = CompanyTickerResolver(
          repository: _FakeSymbolSearchRepository(
            (_) async => const Right([
              SymbolSearchResult(
                symbol: 'META',
                description: 'META PLATFORMS INC',
                type: 'Common Stock',
              ),
              SymbolSearchResult(
                symbol: 'FB',
                description: 'FACEBOOK INC (legacy listing)',
                type: 'Common Stock',
              ),
            ]),
          ),
        );

        final resolution = await resolver.resolve('Facebook');

        expect(resolution.ticker, isNull);
        expect(resolution.matches, hasLength(2));
      },
    );

    test(
      'filters out non-primary listings (symbol with a dot) before '
      'deciding ambiguity — a single primary match still resolves',
      () async {
        final resolver = CompanyTickerResolver(
          repository: _FakeSymbolSearchRepository(
            (_) async => const Right([
              SymbolSearchResult(
                symbol: 'BRK.A',
                description: 'BERKSHIRE HATHAWAY CLASS A (other exchange)',
                type: 'Common Stock',
              ),
              SymbolSearchResult(
                symbol: 'BRK-A',
                description: 'BERKSHIRE HATHAWAY INC-CL A',
                type: 'Common Stock',
              ),
            ]),
          ),
        );

        final resolution = await resolver.resolve('Berkshire');

        expect(resolution.ticker, 'BRK-A');
      },
    );

    test('caps ambiguous matches at 4 candidates', () async {
      final resolver = CompanyTickerResolver(
        repository: _FakeSymbolSearchRepository(
          (_) async => Right([
            for (var i = 0; i < 6; i++)
              SymbolSearchResult(
                symbol: 'SYM$i',
                description: 'COMPANY $i',
                type: 'Common Stock',
              ),
          ]),
        ),
      );

      final resolution = await resolver.resolve('company');

      expect(resolution.matches, hasLength(4));
    });

    test('is notFound when there are no matches at all', () async {
      final resolver = CompanyTickerResolver(
        repository: _FakeSymbolSearchRepository((_) async => const Right([])),
      );

      final resolution = await resolver.resolve('asdfghjkl');

      expect(resolution.ticker, isNull);
      expect(resolution.matches, isNull);
    });

    test('is notFound (not an error) when the query itself fails', () async {
      final resolver = CompanyTickerResolver(
        repository: _FakeSymbolSearchRepository(
          (_) async => Left(HttpError(code: 'network_error')),
        ),
      );

      final resolution = await resolver.resolve('Apple');

      expect(resolution.ticker, isNull);
      expect(resolution.matches, isNull);
    });
  });
}
