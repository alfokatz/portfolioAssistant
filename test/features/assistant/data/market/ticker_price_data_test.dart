import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/data/market/ticker_price_data.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

Map<String, Object?> _period(
  double pct,
  double start,
  double end, {
  String label = 'últimos 7 días',
  bool sufficient = true,
}) => {
  'change_pct': pct,
  'price_start': start,
  'price_end': end,
  'has_sufficient_history': sufficient,
  'label_es': label,
};

ToolCallRecord _quote(
  String ticker, {
  double price = 120.5,
  double? weight,
  Map<String, Object?>? periods,
  bool fetchOk = true,
}) => ToolCallRecord(
  name: 'get_quote',
  args: {
    'tickers': [ticker],
  },
  result: {
    'status': 'ok',
    'tickers': {
      ticker: {
        'fetch_ok': fetchOk,
        'current_price': price,
        if (weight != null) 'weight_pct': weight,
        'periods':
            periods ??
            {
              'day': _period(1.2, 119.07, 120.5, label: 'último día'),
              'week': _period(-2.1, 123.09, 120.5),
              'month': _period(5.8, 113.89, 120.5, label: 'últimos 30 días'),
            },
      },
    },
  },
);

TurnEvidence _evidence(List<ToolCallRecord> calls) =>
    TurnEvidence(calls: calls);

void main() {
  test('the model sends ticker + period; the app fills every number from '
      'get_quote', () {
    final filled = TickerPriceData.fillPayload({
      'ticker': 'nvda',
      'initialRange': '1W',
      'period': 'week',
    }, _evidence([_quote('NVDA', weight: 12.5)]));
    expect(filled, {
      'ticker': 'nvda',
      'initialRange': '1W',
      'period': 'week',
      'currentPrice': 120.5,
      'weightPct': 12.5,
      'dayChangePct': 1.2,
      'weekChangePct': -2.1,
      'monthChangePct': 5.8,
      'periodLabel': 'últimos 7 días',
      'changePct': -2.1,
      'priceStart': 123.09,
      'priceEnd': 120.5,
    });
  });

  test('evidence wins over numbers the model copied (an old answer), and '
      'without evidence the payload stays as it came', () {
    final legacy = {
      'ticker': 'NVDA',
      'initialRange': '1M',
      'currentPrice': 999.0,
      'dayChangePct': 9.9,
    };
    final filled = TickerPriceData.fillPayload(
      legacy,
      _evidence([_quote('NVDA')]),
    );
    expect(filled['currentPrice'], 120.5);
    expect(filled['dayChangePct'], 1.2);

    expect(TickerPriceData.fillPayload(legacy, TurnEvidence.empty), legacy);
    // Otro ticker en la evidencia: no se mezclan.
    expect(
      TickerPriceData.fillPayload(legacy, _evidence([_quote('AAPL')])),
      legacy,
    );
  });

  test('a period without enough history does not show a % chip', () {
    final filled = TickerPriceData.fillPayload(
      {'ticker': 'NEW', 'initialRange': '1M', 'dayChangePct': 3.0},
      _evidence([
        _quote(
          'NEW',
          periods: {
            'day': _period(0, 0, 10, sufficient: false),
            'week': _period(4.0, 9.6, 10),
          },
        ),
      ]),
    );
    expect(filled.containsKey('dayChangePct'), isFalse);
    expect(filled['weekChangePct'], 4.0);
  });

  test('a named window without enough history is not filled; a QaTickerMove '
      'becomes a snapshot ([W:FALLBACK])', () {
    final evidence = _evidence([
      _quote(
        'NEW',
        periods: {
          'week': _period(2.0, 9.8, 10),
          'year': _period(0, 0, 10, label: 'último año', sufficient: false),
        },
      ),
    ]);
    final chart = TickerPriceData.fillPayload({
      'component': 'QaPriceChart',
      'ticker': 'NEW',
      'initialRange': '1Y',
      'period': 'year',
    }, evidence);
    expect(chart.containsKey('changePct'), isFalse);
    expect(chart.containsKey('periodLabel'), isFalse);
    expect(chart['component'], 'QaPriceChart');

    final move = TickerPriceData.fillPayload({
      'component': 'QaTickerMove',
      'ticker': 'NEW',
      'period': 'year',
    }, evidence);
    expect(move['component'], 'QaTickerSnapshot');
    expect(move['currentPrice'], 120.5);
    expect(move['weekChangePct'], 2.0);
  });

  test('a held ticker + period takes the move from position_periods; the '
      'price from get_quote when there is one', () {
    final details = ToolCallRecord(
      name: 'get_portfolio_details',
      args: {
        'include': ['position_periods'],
        'tickers': ['AAPL'],
      },
      result: {
        'status': 'ok',
        'position_periods': {
          'AAPL': {
            'week': {..._period(3.0, 200, 206), 'change_abs': 6.0},
          },
        },
      },
    );
    final onlyDetails = TickerPriceData.fillPayload({
      'ticker': 'AAPL',
      'period': 'week',
      'weightPct': 20.0,
    }, _evidence([details]));
    expect(onlyDetails['changePct'], 3.0);
    expect(onlyDetails['priceStart'], 200);
    expect(onlyDetails['priceEnd'], 206);
    // Sin get_quote el peso queda el que mandó el modelo (del brief).
    expect(onlyDetails['weightPct'], 20.0);
    expect(onlyDetails.containsKey('currentPrice'), isFalse);

    final data = TickerPriceData.from(_evidence([details]), 'aapl')!;
    expect(data.backingNumbers, containsAll([3.0, 200.0, 206.0, 6.0]));
  });

  test('the most recent call with data wins; failed quotes are skipped', () {
    final data =
        TickerPriceData.from(
          _evidence([
            _quote('NVDA', price: 100),
            _quote('NVDA', price: 130),
            _quote('NVDA', price: 0, fetchOk: false),
          ]),
          'NVDA',
        )!;
    expect(data.currentPrice, 130);
    expect(TickerPriceData.from(TurnEvidence.empty, 'NVDA'), isNull);
    expect(
      TickerPriceData.from(_evidence([_quote('NVDA', fetchOk: false)]), 'NVDA'),
      isNull,
    );
  });
}
