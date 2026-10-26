import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/domain/portfolio_diagnosis.dart';

final _now = DateTime(2026, 10, 26);

/// Una posición que hoy vale [value] (compró [value]/[gain] el [bought]).
PositionValuation _pos(
  String ticker,
  double value, {
  double gain = 1,
  DateTime? bought,
}) => PortfolioCalculator.valuate(
  position: Position(
    id: ticker,
    ticker: ticker,
    quantity: 1,
    purchasePrice: value / gain,
    purchaseDate: bought ?? DateTime(2025, 1, 2),
  ),
  currentPrice: value,
);

/// El S&P 500 de [from] a hoy, de [start] a [end] en línea recta.
List<PriceCandle> _sp(DateTime from, double start, double end) {
  final days = _now.difference(from).inDays;
  return [
    for (var i = 0; i <= days; i++)
      PriceCandle(
        date: from.add(Duration(days: i)),
        close: start + (end - start) * i / days,
      ),
  ];
}

PortfolioDiagnosis _build({
  required List<PositionValuation> positions,
  Map<String, String> sectors = const {},
  Map<String, FundLook> funds = const {},
  List<PriceCandle> sp500 = const [],
}) => PortfolioDiagnosisBuilder.build(
  DiagnosisInputs(
    valuations: positions,
    lots: positions,
    sectorByTicker: sectors,
    funds: funds,
    sp500: sp500,
    now: _now,
  ),
);

const _voo = FundLook(
  holdings: {'NVDA': 7, 'AAPL': 6.5, 'MSFT': 6},
  sectors: {'Tecnología': 33, 'Finanzas': 13, 'Salud': 10},
  expenseRatioPct: 0.03,
  stockPct: 99.5,
);
const _qqq = FundLook(
  holdings: {'NVDA': 9, 'AAPL': 8, 'MSFT': 8},
  sectors: {'Tecnología': 60, 'Consumo': 18},
  expenseRatioPct: 0.2,
  stockPct: 100,
);

void main() {
  test('una empresa directa y adentro de dos ETFs: su peso real', () {
    final d = _build(
      positions: [_pos('NVDA', 1000), _pos('VOO', 5000), _pos('QQQ', 4000)],
      funds: {'VOO': _voo, 'QQQ': _qqq},
    );
    final overlap = d.findings.firstWhere(
      (f) => f.kind == DiagnosisKind.overlap,
    );
    expect(overlap.ticker, 'NVDA');
    expect(overlap.via, ['QQQ', 'VOO']);
    // 10 % directo + 50 % × 7 % + 40 % × 9 % = 17,1 %.
    expect(overlap.numbers['direct'], closeTo(10, 0.01));
    expect(overlap.numbers['total'], closeTo(17.1, 0.01));
    // Es lo que no se ve a simple vista: va primero.
    expect(d.findings.first.kind, DiagnosisKind.overlap);
  });

  test('el sector contando lo de adentro de los fondos', () {
    final d = _build(
      positions: [_pos('QQQ', 7000), _pos('KO', 3000)],
      sectors: {'KO': 'Consumo defensivo'},
      funds: {'QQQ': _qqq},
    );
    final sector = d.findings.firstWhere((f) => f.kind == DiagnosisKind.sector);
    expect(sector.sector, 'Tecnología');
    // 70 % × 60 %: 42 %, y a simple vista (solo acciones) 0 %.
    expect(sector.numbers['total'], closeTo(42, 0.01));
    expect(sector.numbers['direct'], 0);
    expect(sector.via, ['QQQ']);
  });

  test('sin sector conocido ("Sin clasificar") no sale nada de sector', () {
    final d = _build(positions: [_pos('ZZZ', 5000), _pos('YYY', 5000)]);
    expect(d.findings.where((f) => f.kind == DiagnosisKind.sector), isEmpty);
  });

  test(
    'una sola concentración: la posición más grande o las 3 más grandes',
    () {
      final d = _build(
        positions: [
          _pos('TSLA', 5000),
          _pos('AMZN', 2000),
          _pos('KO', 1500),
          _pos('PEP', 1000),
          _pos('JNJ', 500),
        ],
      );
      final concentration = d.findings.where(
        (f) =>
            f.kind == DiagnosisKind.topHolding ||
            f.kind == DiagnosisKind.topThree,
      );
      expect(concentration, hasLength(1));
      expect(concentration.single.kind, DiagnosisKind.topHolding);
      expect(concentration.single.ticker, 'TSLA');
      expect(concentration.single.numbers['pct'], closeTo(50, 0.01));
    },
  );

  test('tres fondos amplios arriba no son "3 posiciones concentradas"', () {
    const broad = FundLook(expenseRatioPct: 0.04);
    final d = _build(
      positions: [
        _pos('VOO', 3000),
        _pos('VXUS', 2000),
        _pos('BND', 1500),
        _pos('KO', 1000),
        _pos('JNJ', 1000),
      ],
      funds: {'VOO': broad, 'VXUS': broad, 'BND': broad},
    );
    expect(d.findings.where((f) => f.kind == DiagnosisKind.topThree), isEmpty);
  });

  test(
    'un sector que es casi todo una sola acción no se repite como sector',
    () {
      final d = _build(
        positions: [_pos('TSLA', 8000), _pos('KO', 2000)],
        sectors: {'TSLA': 'Consumo cíclico', 'KO': 'Consumo defensivo'},
      );
      expect(d.findings.where((f) => f.kind == DiagnosisKind.sector), isEmpty);
      expect(
        d.findings.where((f) => f.kind == DiagnosisKind.topHolding),
        hasLength(1),
      );
    },
  );

  test(
    'todo en un solo fondo amplio no es concentración; en una acción, sí',
    () {
      final fund = _build(positions: [_pos('VOO', 5000)], funds: {'VOO': _voo});
      expect(
        fund.findings.where((f) => f.kind == DiagnosisKind.topHolding),
        isEmpty,
      );
      final stock = _build(positions: [_pos('TSLA', 5000)]);
      expect(stock.findings.single.kind, DiagnosisKind.topHolding);
      expect(stock.findings.single.numbers['pct'], 100);
    },
  );

  test('comisiones: lo que cobran por año los fondos', () {
    const pricey = FundLook(expenseRatioPct: 0.75);
    final d = _build(
      positions: [_pos('ARKK', 6000), _pos('VOO', 4000)],
      funds: {'ARKK': pricey, 'VOO': _voo},
    );
    final fees = d.findings.firstWhere((f) => f.kind == DiagnosisKind.fees);
    expect(fees.tone, DiagnosisTone.attention);
    expect(fees.ticker, 'ARKK');
    // 6000 × 0,75 % + 4000 × 0,03 % = 46,2 por año.
    expect(fees.numbers['annual'], closeTo(46.2, 0.01));
  });

  test('contra el S&P 500, compra por compra (no la serie del total)', () {
    // Compró 1000 en enero de 2025 y 1000 en marzo de 2026; el índice va
    // de 100 a 150. Lo mismo en el índice valdría hoy más que su cartera.
    final from = DateTime(2025, 1, 1);
    final sp = _sp(from, 100, 150);
    final first = _pos('KO', 1000, gain: 1.1, bought: DateTime(2025, 1, 2));
    final second = _pos('PEP', 1000, gain: 1.0, bought: DateTime(2026, 3, 2));
    final d = _build(positions: [first, second], sp500: sp);
    final vs = d.findings.firstWhere((f) => f.kind == DiagnosisKind.vsMarket);
    expect(vs.tone, DiagnosisTone.attention);
    expect(vs.numbers['actual'], closeTo(2000, 0.01));
    expect(vs.numbers['market']!, greaterThan(2000));
    expect(vs.numbers['diff_pct']!, lessThan(0));
    expect(vs.numbers['since_year'], 2025);
  });

  test('contra el S&P 500: recién comprado o sin serie, no dice nada', () {
    final sp = _sp(DateTime(2025, 1, 1), 100, 150);
    final recent = _pos(
      'KO',
      1000,
      gain: 0.5,
      bought: _now.subtract(const Duration(days: 5)),
    );
    expect(
      _build(
        positions: [recent],
        sp500: sp,
      ).findings.where((f) => f.kind == DiagnosisKind.vsMarket),
      isEmpty,
    );
    expect(
      _build(
        positions: [_pos('KO', 1000, gain: 2)],
      ).findings.where((f) => f.kind == DiagnosisKind.vsMarket),
      isEmpty,
    );
  });

  test('la peor posición si perdió mucho', () {
    final d = _build(
      positions: [
        _pos('ABC', 3000, gain: 0.6),
        _pos('XYZ', 3000),
        _pos('KO', 3000),
      ],
    );
    final bw = d.findings.firstWhere((f) => f.kind == DiagnosisKind.bestWorst);
    expect(bw.ticker, 'ABC');
    expect(bw.numbers['worst_pct'], closeTo(-40, 0.01));
  });

  test('nada llamativo: "está repartida", en tono bueno', () {
    final d = _build(
      positions: [
        for (final t in ['A', 'B', 'C', 'D', 'E', 'F']) _pos(t, 1000),
      ],
    );
    expect(d.findings.map((f) => f.kind), [DiagnosisKind.spread]);
    expect(d.anyAttention, isFalse);
  });

  test('hasta 3 hallazgos, del más llamativo al menos', () {
    final sp = _sp(DateTime(2025, 1, 1), 100, 150);
    final d = _build(
      positions: [
        _pos('NVDA', 4000, gain: 3),
        _pos('QQQ', 3000),
        _pos('VOO', 2000),
        _pos('ABC', 1000, gain: 0.5),
      ],
      funds: {'QQQ': _qqq, 'VOO': _voo},
      sp500: sp,
    );
    expect(d.findings, hasLength(PortfolioDiagnosis.maxShown));
    final scores = [for (final f in d.findings) f.score];
    expect(scores, [...scores]..sort((a, b) => b.compareTo(a)));
  });

  test('FundLook desde lo que da EtfHoldingsFetcher (símbolos de Yahoo)', () {
    final look = FundLook.fromJson({
      'top_holdings': [
        {'symbol': 'BRK-B', 'weight_pct': 1.6},
        {'symbol': 'AAPL', 'weight_pct': 6.5},
      ],
      'sectors': [
        {'sector': 'Tecnología', 'weight_pct': 31.2},
      ],
      'expense_ratio_pct': 0.03,
      'stock_position_pct': 99.4,
    });
    expect(look.holdings, {'BRK.B': 1.6, 'AAPL': 6.5});
    expect(look.sectors, {'Tecnología': 31.2});
    expect(look.expenseRatioPct, 0.03);
    expect(look.stockPct, 99.4);
  });

  test('sin valor (cotizaciones caídas): sin hallazgos, sin romper', () {
    final d = _build(positions: [_pos('KO', 0)]);
    expect(d.findings, isEmpty);
    expect(d.positions, 0);
  });
}
