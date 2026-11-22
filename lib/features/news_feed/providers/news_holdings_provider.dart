import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

/// Cuánto pesa cada posición en la cartera, en %, por ticker normalizado
/// (`NVDA` → 18,2). Sale del valor de mercado de la Home (el mismo número de
/// las posiciones); vacío sin cartera o con valor cero. Es lo que dice el
/// chip "Tenés NVDA · 18 % de tu cartera".
final newsHoldingWeightsProvider = Provider<Map<String, double>>((ref) {
  PortfolioSummary? summary;
  try {
    summary = ref.watch(homeProvider.select((s) => s.summary));
  } catch (_) {
    // Sin cartera disponible (sesión cerrándose): sin pesos, el chip dice
    // solo "Tenés NVDA".
    return const {};
  }
  if (summary == null) return const {};
  final values = <String, double>{};
  var total = 0.0;
  for (final v in summary.valuations) {
    final mv = v.marketValue;
    if (!mv.isFinite || mv <= 0) continue;
    final key = PortfolioCalculator.normalizeTicker(v.position.ticker);
    values[key] = (values[key] ?? 0) + mv;
    total += mv;
  }
  if (total <= 0) return const {};
  return {for (final e in values.entries) e.key: e.value / total * 100};
});

/// La variación del día de los tickers que movieron la cartera en el último
/// cierre (los `movers` del brief, los mismos números de la Home). Un ticker
/// que no movió lo suficiente para figurar no está: nunca se inventa.
final newsHoldingDayMovesProvider = Provider<Map<String, double>>((ref) {
  final movers = ref.watch(
    dailyBriefControllerProvider.select((s) => s.brief?.numbers.movers),
  );
  if (movers == null) return const {};
  return {
    for (final m in movers)
      if (m.pct.isFinite) PortfolioCalculator.normalizeTicker(m.ticker): m.pct,
  };
});
