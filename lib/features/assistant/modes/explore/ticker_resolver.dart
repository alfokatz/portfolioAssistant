import 'package:portfolio_assistant/features/assistant/modes/explore/broad_market_query.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/company_query_extractor.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/ticker_extractor.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/yahoo_ticker_search_client.dart';

/// Resuelve tickers desde símbolos explícitos o búsqueda por nombre de empresa.
abstract final class TickerResolver {
  static const maxTickers = 3;

  static Future<List<String>> resolveTickers(
    String message, {
    YahooTickerSearchClient? searchClient,
    bool allowBroadMarketProxy = true,
  }) async {
    final symbols = TickerExtractor.extractSymbolTickers(message);
    if (symbols.isNotEmpty) return symbols;

    if (allowBroadMarketProxy && isBroadMarketQuery(message)) {
      return [broadMarketProxyTicker];
    }

    final client = searchClient ?? YahooTickerSearchClient();
    final query = CompanyQueryExtractor.fromMessage(message);
    if (query == null) return const [];

    final hits = await client.search(query, limit: maxTickers);
    if (hits.isEmpty) {
      final fallbackHits = await client.search(message.trim(), limit: maxTickers);
      return fallbackHits.map((hit) => hit.symbol).toList();
    }

    return hits.map((hit) => hit.symbol).toList();
  }
}
