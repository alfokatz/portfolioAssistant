import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/translate/app_language.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_repository.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_numbers.dart';
import 'package:portfolio_assistant/features/news_feed/domain/news_bundle.dart';

/// Qué bloque de `daily-brief` se pide (§3.5).
enum NewsScope { feed, topic, market }

/// El feed, el detalle de un tema y "Mercado hoy": los tres salen de la edge
/// function `daily-brief` (por [DailyBriefStore], que usa `PortyEdgeClient`).
/// El cliente nunca manda tickers: el servidor lee la cartera de la base.
class NewsFeedRepository {
  NewsFeedRepository(
    this._store, {
    DateTime Function()? clock,
    String Function()? language,
  }) : _clock = clock ?? DateTime.now,
       _language = language ?? (() => AppLanguage.code);

  final DailyBriefStore _store;
  final DateTime Function() _clock;
  final String Function() _language;

  /// `daily_brief_status()`: el interruptor y las piezas. Nunca lanza.
  Future<DailyBriefStatus> status() => _store.status();

  /// Lanza [DailyBriefFailure] (`disabled`, `network`, `server`).
  Future<NewsBundle> load(NewsScope scope, {String? topicId}) async {
    final body = await _store.bundle(
      scope.name,
      day: DailyBriefNumbers.dayKey(_clock()),
      lang: _language(),
      topic: scope == NewsScope.topic ? topicId : null,
    );
    return NewsBundle.parse(body);
  }
}

final newsFeedRepositoryProvider = Provider<NewsFeedRepository>(
  (ref) => NewsFeedRepository(ref.watch(dailyBriefRepositoryProvider)),
);
