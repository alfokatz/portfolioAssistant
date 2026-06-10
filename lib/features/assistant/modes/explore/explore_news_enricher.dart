import 'package:portfolio_assistant/features/assistant/modes/explore/news_query_detector.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/news_source_parser.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/ticker_extractor.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_raw_chat_client.dart';

class ExploreNewsEnricher {
  ExploreNewsEnricher({OpenAIRawChatClient? client})
      : _client = client ?? OpenAIRawChatClient();

  final OpenAIRawChatClient _client;

  /// Adds [news_sources] and [news_enrichment] to [snapshot] if [userMessage]
  /// is a news query.
  ///
  /// [news_enrichment] is one of: `skipped`, `ok`, `empty`, `failed`.
  Future<Map<String, Object?>> enrich({
    required Map<String, Object?> snapshot,
    required String userMessage,
  }) async {
    if (!isNewsQuery(userMessage)) {
      return {
        ...snapshot,
        'news_sources': <Object?>[],
        'news_enrichment': 'skipped',
      };
    }

    try {
      final tickers = TickerExtractor.extractTickers(userMessage);
      final rawText = await _client.searchNews(
        userQuery: userMessage,
        tickers: tickers,
      );
      final sources = ExploreNewsSourceParser.parse(rawText);

      return {
        ...snapshot,
        'news_sources': sources.map((source) => source.toJson()).toList(),
        'news_enrichment': sources.isEmpty ? 'empty' : 'ok',
      };
    } catch (_) {
      return {
        ...snapshot,
        'news_sources': <Object?>[],
        'news_enrichment': 'failed',
      };
    }
  }
}
