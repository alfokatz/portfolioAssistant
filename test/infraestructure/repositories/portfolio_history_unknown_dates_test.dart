// Compras sin fecha conocida (un bróker que no la informa por SnapTrade):
// el gráfico de la Home las cuenta como que ya estaban, en vez de una
// compra de hoy que dejaba el gráfico vacío.
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/supabase/supabase_portfolio_mapper.dart';
import 'package:portfolio_assistant/infraestructure/repositories/portfolio_analytics_repository_impl.dart';

class _Positions implements PositionRepository {
  _Positions(this.positions);

  final List<Position> positions;

  @override
  Future<Either<HttpError, List<Position>>> getPositions() async =>
      Right(positions);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Un cierre por día, los últimos 400 días, a 100.
class _Quotes implements QuoteRepository {
  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker, {
    Object? range,
  }) async {
    final today = DateTime.now();
    return Right([
      for (var i = 400; i >= 0; i--)
        PriceCandle(
          date: DateTime(today.year, today.month, today.day - i),
          close: 100,
        ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Position _lot({required bool known}) => Position(
  id: known ? 'k' : 'u',
  ticker: 'VOO',
  quantity: 2,
  purchasePrice: 90,
  // La de la importación: hoy.
  purchaseDate: DateTime.now(),
  source: PositionSource.snaptrade,
  purchaseDateKnown: known,
);

void main() {
  PortfolioAnalyticsRepositoryImpl repo(List<Position> positions) =>
      PortfolioAnalyticsRepositoryImpl(
        positionRepository: _Positions(positions),
        quoteRepository: _Quotes(),
      );

  test('unknown purchase date: the chart covers the last year', () async {
    final history = (await repo([_lot(known: false)]).getPortfolioHistory())
        .getOrElse(() => []);
    expect(history.length, greaterThan(300));
    expect(history.first.totalValue, 200);
  });

  test('a purchase really made today (known) has no history yet', () async {
    // Lo que pasaba antes con todo lo de SnapTrade: el gráfico vacío.
    final history = (await repo([_lot(known: true)]).getPortfolioHistory())
        .getOrElse(() => []);
    expect(history, isEmpty);
  });

  test('the mapper reads purchase_date_known (old rows: known)', () {
    Map<String, dynamic> row([Object? known]) => {
      'id': 'p',
      'ticker': 'VOO',
      'quantity': 1,
      'purchase_price': 1,
      'purchase_date': '2026-11-02T00:00:00Z',
      if (known != null) 'purchase_date_known': known,
    };
    expect(
      SupabasePortfolioMapper.positionFromRow(row(false)).purchaseDateKnown,
      isFalse,
    );
    expect(
      SupabasePortfolioMapper.positionFromRow(row()).purchaseDateKnown,
      isTrue,
    );
  });
}
