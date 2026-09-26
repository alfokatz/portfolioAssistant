import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';

/// Períodos del selector de `QaPriceChart`. [wireValue] es lo que manda el
/// modelo en `initialRange`.
enum PriceChartRange {
  day('1D', '1D', null),
  week('1W', '1W', Duration(days: 7)),
  month('1M', '1M', Duration(days: 30)),
  quarter('3M', '3M', Duration(days: 90)),
  year('1Y', '1Y', Duration(days: 365)),
  all('ALL', 'Todo', null);

  const PriceChartRange(this.wireValue, this.label, this.lookback);

  final String wireValue;
  final String label;

  /// Ventana hacia atrás desde el último cierre diario. `null` para [day]
  /// (usa velas intradía) y [all] (todo el histórico).
  final Duration? lookback;

  static PriceChartRange fromWire(String? value) {
    for (final range in values) {
      if (range.wireValue == value) return range;
    }
    return PriceChartRange.month;
  }
}

/// Resuelve la serie de precios de un ticker para un [PriceChartRange].
///
/// Devuelve `null` cuando no hay datos utilizables — sin distinguir la
/// causa (ticker sin histórico, falla del histórico diario, o falla del
/// endpoint intradía de Yahoo): el widget tiene un solo camino de fallback
/// para todas.
class PriceChartDataLoader {
  PriceChartDataLoader(this._quoteRepository);

  final QuoteRepository _quoteRepository;

  /// Tope de puntos a dibujar: "Todo" puede traer miles de cierres diarios
  /// y ni el painter ni el scrub necesitan más resolución que el ancho del
  /// gráfico.
  static const maxPoints = 320;

  Future<List<PriceCandle>?> load(String ticker, PriceChartRange range) async {
    final candles = range == PriceChartRange.day
        ? await _quoteRepository.getIntradayCandles(ticker)
        : await _loadDaily(ticker, range);
    if (candles == null || candles.length < 2) return null;
    return downsample(candles, maxPoints);
  }

  Future<List<PriceCandle>?> _loadDaily(
    String ticker,
    PriceChartRange range,
  ) async {
    final result = await _quoteRepository.getHistoricalDaily(ticker);
    final history = result.fold((_) => null, (list) => list);
    if (history == null || history.isEmpty) return null;
    final lookback = range.lookback;
    if (lookback == null) return history;
    final cutoff = history.last.date.subtract(lookback);
    return history.where((c) => !c.date.isBefore(cutoff)).toList();
  }

  /// Muestreo uniforme que conserva siempre el primer y el último punto
  /// (el precio actual y el inicio del rango no pueden perderse).
  static List<PriceCandle> downsample(List<PriceCandle> candles, int max) {
    if (candles.length <= max) return candles;
    final step = (candles.length - 1) / (max - 1);
    return [
      for (var i = 0; i < max; i++) candles[(i * step).round()],
    ];
  }
}

final priceChartDataLoaderProvider = Provider<PriceChartDataLoader>(
  (ref) => PriceChartDataLoader(ref.watch(quoteRepositoryProvider)),
);
