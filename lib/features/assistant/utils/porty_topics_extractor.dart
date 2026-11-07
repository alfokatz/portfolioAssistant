import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/porty_topic.dart';

/// De qué tickers habló el usuario en un turno, para `porty_topics`. Sale de
/// las tools que corrieron (sin el modelo), pero solo cuenta lo que el
/// usuario pidió, no lo que el modelo eligió por su cuenta (candidatos de
/// una idea de inversión, los que más movieron la cartera):
///
/// - el ticker está escrito en la pregunta, o
/// - salió de buscar un nombre (`search_symbol`: "¿qué pasa con Amazon?"), o
/// - es el de la pantalla desde donde preguntó, o
/// - el turno miró uno o dos tickers en total (una pregunta puntual).
abstract final class PortyTopicsExtractor {
  /// Tools que miran tickers puntuales.
  static const tickerTools = {
    'get_quote',
    'get_news',
    'get_fundamentals',
    'get_earnings',
    'get_etf_holdings',
    'get_dividends',
  };

  /// Cuántos se registran por turno como máximo.
  static const maxPerTurn = 3;

  static List<PortyTopicDraft> extract({
    required String question,
    required List<ToolCallRecord> calls,
    required Set<String> heldTickers,
    String? screenTicker,
  }) {
    final looked = <String>{};
    final prices = <String, double>{};
    final resolved = <String>{};
    for (final call in calls) {
      if (call.name == 'search_symbol' && call.status == 'resolved') {
        final t = call.result['ticker'];
        if (t is String) resolved.add(t.toUpperCase());
      }
      if (!tickerTools.contains(call.name)) continue;
      if (call.status == 'locked' || call.status == 'invalid') continue;
      final tickers = call.args['tickers'];
      if (tickers is! List) continue;
      for (final t in tickers) {
        if (t is String && t.trim().isNotEmpty) {
          looked.add(t.trim().toUpperCase());
        }
      }
      if (call.name == 'get_quote') {
        final byTicker = call.result['tickers'];
        if (byTicker is Map) {
          for (final MapEntry(:key, :value) in byTicker.entries) {
            if (value is Map && value['fetch_ok'] == true) {
              final price = value['current_price'];
              if (price is num && price > 0) {
                prices['$key'.toUpperCase()] = price.toDouble();
              }
            }
          }
        }
      }
    }
    if (looked.isEmpty) return const [];

    final upperQuestion = question.toUpperCase();
    bool named(String ticker) => RegExp(
      '(^|[^A-Z0-9])${RegExp.escape(ticker)}(\$|[^A-Z0-9])',
    ).hasMatch(upperQuestion);
    final screen = screenTicker?.toUpperCase();
    final pointed = looked.length <= 2;

    final clipped =
        question.trim().length <= 200
            ? question.trim()
            : '${question.trim().substring(0, 199)}…';
    return [
      for (final t in looked)
        if (pointed || named(t) || resolved.contains(t) || t == screen)
          PortyTopicDraft(
            ticker: t,
            question: clipped,
            priceAt: prices[t],
            held: heldTickers.contains(t),
          ),
    ].take(maxPerTurn).toList();
  }
}
