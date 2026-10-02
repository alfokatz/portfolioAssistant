import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/investor_pulse_item.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/investor_pulse_relevance.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/report_week.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_portfolio_numbers.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_input.dart';

final fixtureWeek = ReportWeek.ofMonday(DateTime(2026, 9, 21));

PriceCandle _c(int day, double close) =>
    PriceCandle(date: DateTime.utc(2026, 9, day, 13, 30), close: close);

List<PriceCandle> _week(double before, double end) => [
  _c(18, before),
  _c(21, before),
  _c(22, before),
  _c(23, before),
  _c(24, end),
  _c(25, end),
];

Position _lot(String t, double qty) => Position(
  id: t,
  ticker: t,
  quantity: qty,
  purchasePrice: 50,
  purchaseDate: DateTime(2026, 1, 5),
);

/// Semana de ejemplo: AAPL +10% (lo que más movió), MSFT −5%, una noticia
/// de cada una, un Form 4 de Berkshire sobre LEN (que no tiene), una nota de
/// Ackman sobre MSFT (que sí tiene) y earnings de MSFT la semana siguiente.
WeeklyReportInput fixtureInput({
  bool withNews = true,
  bool withInvestors = true,
}) {
  final numbers = WeeklyPortfolioCalculator.compute(
    week: fixtureWeek,
    lots: [_lot('AAPL', 10), _lot('MSFT', 5)],
    candles: {'AAPL': _week(100, 110), 'MSFT': _week(200, 190)},
    benchmark: _week(5000, 5050),
  );
  final investors = [
    InvestorPulseItem.tryParse({
      'id': 'i1',
      'investor_id': 'warren-buffett',
      'investor_name': 'Warren Buffett',
      'organization': 'Berkshire Hathaway',
      'voice': 'investor',
      'type': 'filing',
      'form': '4',
      'action': 'buy',
      'issuer_name': 'LENNAR CORP /NEW/',
      'issuer_ticker': 'LEN',
      'shares': 638813,
      'date': '2026-09-25',
      'url': 'https://www.sec.gov/x-index.htm',
    })!,
    InvestorPulseItem.tryParse({
      'id': 'i2',
      'investor_id': 'bill-ackman',
      'investor_name': 'Bill Ackman',
      'organization': 'Pershing Square',
      'voice': 'investor',
      'type': 'news',
      'headline': 'Bill Ackman says Microsoft stock is his top AI bet',
      'source': 'CNBC',
      'date': '2026-09-24',
      'url': 'https://news.google.com/i2',
    })!,
  ];
  return WeeklyReportInput(
    numbers: numbers,
    news:
        withNews
            ? [
              WeeklyNewsItem(
                id: 'n1',
                ticker: 'AAPL',
                headline: 'Apple shares jump after strong iPhone 18 preorders',
                source: 'Reuters',
                url: 'https://news.google.com/n1',
                publishedAt: DateTime.utc(2026, 9, 24),
              ),
              WeeklyNewsItem(
                id: 'n2',
                ticker: 'MSFT',
                headline: 'Microsoft faces EU antitrust probe over cloud deals',
                source: 'Bloomberg',
                url: 'https://news.google.com/n2',
                publishedAt: DateTime.utc(2026, 9, 23),
              ),
            ]
            : const [],
    upcomingEarnings: [
      UpcomingEarnings(
        ticker: 'MSFT',
        date: DateTime(2026, 9, 30),
        timingLabel: 'Después del cierre',
      ),
    ],
    newsFailed: false,
    earningsFailed: false,
    investors:
        withInvestors
            ? InvestorPulseRelevance.rank(
              investors,
              holdings: {'AAPL': 'Apple Inc', 'MSFT': 'Microsoft Corp'},
              limit: 8,
            )
            : const [],
  );
}
