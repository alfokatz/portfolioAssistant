import 'package:portfolio_assistant/features/assistant/tools/market_tools.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';

/// Una posición de un ETF.
class EtfHolding {
  const EtfHolding({required this.symbol, this.name, this.weightPct});

  final String symbol;
  final String? name;
  final double? weightPct;
}

/// Peso de un sector dentro del ETF (sector ya en español).
class EtfSectorWeight {
  const EtfSectorWeight({required this.sector, required this.weightPct});

  final String sector;
  final double weightPct;
}

/// La composición de un ETF tal como la trajo `get_etf_holdings` en la
/// conversación — nunca lo que escribió el modelo: la card `QaEtfHoldings`
/// pone cada nombre y peso desde acá. Si se pidió varias veces, gana la
/// llamada más reciente con dato para el ticker.
class EtfHoldingsData {
  const EtfHoldingsData({
    required this.ticker,
    this.fundName,
    this.category,
    this.expenseRatioPct,
    this.totalAssetsUsd,
    this.holdings = const [],
    this.topHoldingsWeightPct,
    this.sectors = const [],
  });

  final String ticker;
  final String? fundName;
  final String? category;
  final double? expenseRatioPct;
  final double? totalAssetsUsd;
  final List<EtfHolding> holdings;
  final double? topHoldingsWeightPct;
  final List<EtfSectorWeight> sectors;

  bool get isEmpty => holdings.isEmpty && sectors.isEmpty;

  /// `null` si ninguna llamada ok trajo composición para [ticker].
  static EtfHoldingsData? from(TurnEvidence evidence, String ticker) {
    final t = ticker.toUpperCase();
    for (final call in evidence.calls.reversed) {
      if (call.name != GetEtfHoldingsTool.toolName || call.status != 'ok') {
        continue;
      }
      final etfs = call.result['etfs'];
      final entry = etfs is Map ? etfs[t] : null;
      if (entry is Map) return fromJson(t, entry);
    }
    return null;
  }

  static EtfHoldingsData fromJson(String ticker, Map<dynamic, dynamic> json) {
    return EtfHoldingsData(
      ticker: ticker,
      fundName: _string(json['fund_name']),
      category: _string(json['category']),
      expenseRatioPct: _number(json['expense_ratio_pct']),
      totalAssetsUsd: _number(json['total_assets_usd']),
      holdings: [
        for (final h in (json['top_holdings'] as List? ?? const []))
          if (h is Map && _string(h['symbol']) != null)
            EtfHolding(
              symbol: _string(h['symbol'])!,
              name: _string(h['name']),
              weightPct: _number(h['weight_pct']),
            ),
      ],
      topHoldingsWeightPct: _number(json['top_holdings_weight_pct']),
      sectors: [
        for (final s in (json['sectors'] as List? ?? const []))
          if (s is Map &&
              _string(s['sector']) != null &&
              _number(s['weight_pct']) != null)
            EtfSectorWeight(
              sector: _string(s['sector'])!,
              weightPct: _number(s['weight_pct'])!,
            ),
      ],
    );
  }

  /// Todos los números de la card, para el chequeo de que el texto del
  /// modelo no cite cifras que no están en los datos.
  Iterable<double> get backingNumbers sync* {
    if (expenseRatioPct != null) yield expenseRatioPct!;
    if (totalAssetsUsd != null) yield totalAssetsUsd!;
    if (topHoldingsWeightPct != null) yield topHoldingsWeightPct!;
    for (final h in holdings) {
      if (h.weightPct != null) yield h.weightPct!;
    }
    for (final s in sectors) {
      yield s.weightPct;
    }
  }

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static double? _number(Object? value) =>
      value is num ? value.toDouble() : null;
}
