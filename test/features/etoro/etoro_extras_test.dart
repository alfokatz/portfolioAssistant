import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/use_cases/get_position_lots_by_ticker_use_case.dart';
import 'package:portfolio_assistant/features/assistant/services/company_brand_loader.dart';
import 'package:portfolio_assistant/features/etoro/domain/etoro_connection.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/supabase/supabase_portfolio_mapper.dart';
import 'package:portfolio_assistant/infraestructure/repositories/portfolio_analytics_repository_impl.dart';

/// Cotizaciones: solo los tickers de [prices]; el resto falla (sin dato).
class _Quotes implements QuoteRepository {
  _Quotes([this.prices = const {}]);
  final Map<String, double> prices;

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async {
    final p = prices[ticker];
    return p == null
        ? Left(HttpError(code: 'no_quote', message: 'sin cotización'))
        : Right(p);
  }

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async => const Right([]);

  @override
  Future<List<PriceCandle>> getIntradayCandles(String ticker) async => [];
}

class _Positions implements PositionRepository {
  _Positions(this.positions);
  final List<Position> positions;

  @override
  Future<Either<HttpError, List<Position>>> getPositions() async =>
      Right(positions);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Brands implements CompanyBrandRepository {
  _Brands(this.brands);
  final Map<String, CompanyBrand> brands;

  @override
  Future<CompanyBrand?> getBrand(String ticker) async =>
      brands[ticker] ?? CompanyBrand(ticker: ticker);
}

Position _lot(
  String id,
  String ticker, {
  double purchasePrice = 100,
  double? brokerPrice,
  PositionSource source = PositionSource.etoro,
}) => Position(
  id: id,
  ticker: ticker,
  quantity: 2,
  purchasePrice: purchasePrice,
  purchaseDate: DateTime(2026, 1, 1),
  source: source,
  brokerPrice: brokerPrice,
);

void main() {
  group('precio de eToro como respaldo', () {
    test('el mapper lo lee y nunca lo manda al guardar', () {
      final p = SupabasePortfolioMapper.positionFromRow({
        'id': 'x',
        'ticker': 'ASML',
        'quantity': 1,
        'purchase_price': 600,
        'purchase_date': '2026-01-01T00:00:00Z',
        'source': 'etoro',
        'broker_price': '712.4',
      });
      expect(p.brokerPrice, 712.4);
      final manual = SupabasePortfolioMapper.positionFromRow({
        'id': 'y',
        'ticker': 'AAPL',
        'quantity': 1,
        'purchase_price': 100,
        'purchase_date': '2026-01-01T00:00:00Z',
      });
      expect(manual.brokerPrice, isNull);
      expect(
        SupabasePortfolioMapper.positionToRow(position: p, userId: 'u'),
        isNot(contains('broker_price')),
      );
    });

    test(
      'Inicio: sin cotización usa el precio de eToro (también para los '
      'lotes manuales del mismo ticker); con cotización, la cotización',
      () async {
        final repo = PortfolioAnalyticsRepositoryImpl(
          positionRepository: _Positions([
            _lot('e1', 'XYZ', brokerPrice: 150),
            _lot('m1', 'XYZ', source: PositionSource.manual),
            _lot('e2', 'AAPL', brokerPrice: 150),
            _lot('m2', 'MSFT', source: PositionSource.manual),
          ]),
          quoteRepository: _Quotes({'AAPL': 200}),
        );
        final summary = (await repo.getSummary()).getOrElse(
          () => throw StateError('falló'),
        );
        final prices = {
          for (final l in summary.lots) l.position.id: l.currentPrice,
        };
        expect(prices, {
          'e1': 150, // sin cotización → eToro
          'm1': 150, // mismo ticker → mismo precio
          'e2': 200, // con cotización → la propia
          'm2': 100, // manual sin eToro → precio de compra, como siempre
        });
        final xyz = summary.valuations.firstWhere(
          (v) => v.position.ticker == 'XYZ',
        );
        expect(xyz.pnlAbsolute, closeTo(200, 1e-9)); // 4 acciones × (150 − 100)
      },
    );

    test(
      'Detalle: los lotes sin cotización se valúan con el precio de eToro',
      () async {
        final useCase = GetPositionLotsByTickerUseCase(
          positionRepository: _Positions([
            _lot('m1', 'XYZ', source: PositionSource.manual),
            _lot('e1', 'XYZ', brokerPrice: 150),
          ]),
          quoteRepository: _Quotes(),
        );
        final lots = (await useCase.call(
          params: 'XYZ',
        )).getOrElse(() => throw StateError('falló'));
        expect(lots.map((l) => l.currentPrice).toSet(), {150});
      },
    );
  });

  group('logos de eToro', () {
    test('se usan solo si Finnhub no tiene logo', () async {
      final etoroLogos = {
        'BTC': 'https://etoro/btc.png',
        'AAPL': 'https://etoro/aapl.png',
      };
      final loader = CompanyBrandLoader(
        _Brands({
          'AAPL': CompanyBrand(
            ticker: 'AAPL',
            name: 'Apple',
            logoUrl: 'https://finnhub/aapl.png',
          ),
        }),
        fallbackLogo: (t) => etoroLogos[t],
      );
      expect((await loader.load('AAPL')).logoUrl, 'https://finnhub/aapl.png');
      expect((await loader.load('btc')).logoUrl, 'https://etoro/btc.png');
      expect((await loader.load('ZZZ')).logoUrl, isNull);
    });

    test(
      'un logo que llega después (otro sync) aparece sin vaciar el caché',
      () async {
        final etoroLogos = <String, String>{};
        final loader = CompanyBrandLoader(
          _Brands({}),
          fallbackLogo: (t) => etoroLogos[t],
        );
        expect((await loader.load('ASML')).logoUrl, isNull);
        etoroLogos['ASML'] = 'https://etoro/asml.png';
        expect(loader.peek('ASML')!.logoUrl, 'https://etoro/asml.png');
        expect((await loader.load('ASML')).logoUrl, 'https://etoro/asml.png');
      },
    );
  });

  group('resultado del sync', () {
    test('lee efectivo, otros activos y logos', () {
      final r = EtoroImportResult.fromJson({
        'imported': 3,
        'cashUsd': 1250.5,
        'otherHoldings': [
          {
            'ticker': 'BTC',
            'name': 'Bitcoin',
            'reason': 'crypto',
            'count': 2,
            'units': 0.03,
            'investedUsd': 1950,
            'valueUsd': 1900,
            'pnlUsd': -50,
          },
          {
            'ticker': 'BP.L',
            'reason': 'non_us',
            'count': 1,
            'units': 100,
            'investedUsd': 600,
            'valueUsd': 650,
            'pnlUsd': 50,
          },
        ],
        'logos': {'btc': 'https://etoro/btc.png', 'BAD': 'http://inseguro'},
      });
      expect(r.cashUsd, 1250.5);
      expect(r.otherHoldings.map((h) => h.reason), [
        EtoroSkipReason.crypto,
        EtoroSkipReason.nonUs,
      ]);
      expect(r.otherHoldingsValueUsd, 2550);
      expect(r.otherHoldingsPnlUsd, 0);
      expect(r.otherHoldings.first.pnlPercent, closeTo(-2.564, 0.001));
      expect(r.logos, {'BTC': 'https://etoro/btc.png'});
      expect(r.hasExtras, isTrue);
    });

    test('un resultado viejo (sin los campos nuevos) sigue leyéndose', () {
      final r = EtoroImportResult.fromJson({'imported': 3});
      expect(r.cashUsd, isNull);
      expect(r.otherHoldings, isEmpty);
      expect(r.logos, isEmpty);
      expect(r.hasExtras, isFalse);
    });

    test('efectivo en 0 y nada más → no hay card', () {
      expect(EtoroImportResult.fromJson({'cashUsd': 0}).hasExtras, isFalse);
    });
  });
}
