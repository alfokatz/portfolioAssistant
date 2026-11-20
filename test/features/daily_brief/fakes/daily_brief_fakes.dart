// Fakes y datos de ejemplo del brief diario: el almacén (RPC y edge function)
// con respuestas a elección, un escritor de Porty falso, cotizaciones con
// velas fijas y los fixtures JSON del contrato (test/fixtures/daily_brief).
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_repository.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_writer.dart';

/// El body de un fixture del contrato (`bundle_brief_full`, …).
Map<String, Object?> bundleFixture(String name) =>
    (jsonDecode(File('test/fixtures/daily_brief/$name.json').readAsStringSync())
            as Map)
        .cast<String, Object?>();

/// Jueves 26/11/2026, 8:00: el brief cubre el cierre del miércoles 25.
DateTime briefNow() => DateTime(2026, 11, 26, 8);
const briefDay = '2026-11-26';

Position lot(String ticker, double qty) => Position(
  id: ticker,
  ticker: ticker,
  quantity: qty,
  purchasePrice: 100,
  purchaseDate: DateTime(2026, 1, 5),
);

/// NVDA 10 × (100 → 104,1) y AAPL 20 × (200 → 199): la cartera sube.
final lots = [lot('NVDA', 10), lot('AAPL', 20)];

final candles = <String, List<PriceCandle>>{
  'NVDA': [
    PriceCandle(date: DateTime(2026, 11, 24), close: 100),
    PriceCandle(date: DateTime(2026, 11, 25), close: 104.1),
  ],
  'AAPL': [
    PriceCandle(date: DateTime(2026, 11, 24), close: 200),
    PriceCandle(date: DateTime(2026, 11, 25), close: 199),
  ],
};

List<PortfolioHistoryPoint> history() => [
  PortfolioHistoryPoint(
    date: DateTime(2026, 11, 24),
    totalValue: 10 * 100 + 20 * 200,
    totalCostBasis: 3000,
  ),
  PortfolioHistoryPoint(
    date: DateTime(2026, 11, 25),
    totalValue: 10 * 104.1 + 20 * 199,
    totalCostBasis: 3000,
  ),
];

class FakeQuotes implements QuoteRepository {
  FakeQuotes([Map<String, List<PriceCandle>>? series]) : series = series ?? candles;
  final Map<String, List<PriceCandle>> series;

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async {
    final c = series[ticker];
    return c == null ? Left(HttpError(code: 'unknown')) : Right(c);
  }

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async =>
      Left(HttpError(code: 'unknown'));

  @override
  Future<List<PriceCandle>> getIntradayCandles(String ticker) async => const [];
}

/// `DailyBriefStore` en memoria: responde lo que se le configure y anota lo
/// que recibe.
class FakeDailyBriefStore implements DailyBriefStore {
  FakeDailyBriefStore({
    this.statusResult = const DailyBriefStatus(enabled: true),
    this.claims = const [BriefClaimNumbersOnly()],
    Map<String, Object?>? bundleBody,
    this.bundleError,
  }) : bundleBody = bundleBody ?? bundleFixture('bundle_brief_numbers');

  DailyBriefStatus statusResult;

  /// Respuestas de `claim` en orden (la última se repite).
  List<DailyBriefClaim> claims;
  Map<String, Object?> bundleBody;
  DailyBriefFailure? bundleError;

  var statusCalls = 0;
  var claimCalls = 0;
  var failCalls = 0;
  final bundleCalls = <String>[];
  final completed = <Map<String, Object?>>[];

  @override
  Future<DailyBriefStatus> status() async {
    statusCalls++;
    return statusResult;
  }

  @override
  Future<DailyBriefClaim> claim(String day) async =>
      claims[(claimCalls++).clamp(0, claims.length - 1)];

  @override
  Future<bool> complete(String day, Map<String, Object?> payload) async {
    completed.add(payload);
    return true;
  }

  @override
  Future<void> fail(String day) async => failCalls++;

  @override
  Future<Map<String, Object?>> bundle(
    String scope, {
    required String day,
    required String lang,
    String? topic,
  }) async {
    bundleCalls.add(scope);
    final error = bundleError;
    if (error != null) throw error;
    return bundleBody;
  }
}

/// Porty falso: devuelve la prosa que se le dé y anota los pedidos.
class FakeDailyBriefWriter implements DailyBriefWriter {
  FakeDailyBriefWriter({this.writing});

  DailyBriefWriting? writing;
  final requests = <DailyBriefWritingRequest>[];

  @override
  Future<DailyBriefWriting> write(DailyBriefWritingRequest request) async {
    requests.add(request);
    return writing ??
        const DailyBriefWriting(
          prose: DailyBriefProse(
            why: [
              BriefLine(
                ticker: 'NVDA',
                text: 'Subió 4,1 % el día que presentó resultados.',
                newsId: 'h1',
              ),
            ],
            held: [
              BriefLine(
                ticker: 'AAPL',
                text: 'Apple presentó una nueva línea de productos.',
                newsId: 'h3',
              ),
            ],
            connections: {
              'bonds_rates': 'Tenés bonos o ETF de renta fija, que se mueven con las tasas.',
            },
          ),
          rounds: 1,
        );
  }
}
