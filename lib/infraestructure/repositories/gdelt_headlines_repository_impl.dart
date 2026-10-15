import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/repositories/company_news_repository.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';

/// Titulares de la edge function `headlines` (GDELT filtrado por la lista
/// de medios permitidos del servidor). Solo título, medio, fecha y link:
/// sin imagen ni texto del artículo.
///
/// GDELT admite un pedido cada ~5 s para todo Porty, así que los pedidos
/// que llegan juntos (los tickers de un turno, la cartera del informe
/// semanal) se agrupan en UNA llamada de hasta 10 tickers.
///
/// Nunca lanza. `Left(plan_required)` si el servidor dice que no está en el
/// plan.
class GdeltHeadlinesRepositoryImpl implements CompanyNewsRepository {
  GdeltHeadlinesRepositoryImpl({
    PortyEdgeClient? client,
    this.batchWindow = const Duration(milliseconds: 400),
  }) : _client = client ?? PortyEdgeClient();

  static const maxTickersPerCall = 10;

  final PortyEdgeClient _client;

  /// Cuánto se espera a que lleguen los demás tickers del turno (cada uno
  /// busca antes el nombre de su empresa, así que no llegan juntos).
  final Duration batchWindow;
  final _pending = <String, _Batch>{};

  @override
  Future<Either<HttpError, List<CompanyNewsItem>>> getRecentNews(
    String ticker, {
    int limit = 3,
    DateTime? from,
    DateTime? to,
  }) async {
    final windowed = from != null && to != null;
    final key = windowed ? '${_day(from)}|${_day(to)}' : '';
    final batch = _pending.putIfAbsent(key, () {
      final b = _Batch(from: windowed ? from : null, to: windowed ? to : null);
      Timer(batchWindow, () {
        _pending.remove(key);
        _flush(b);
      });
      return b;
    });
    final completer = batch.waiters.putIfAbsent(
      ticker.toUpperCase(),
      Completer<Either<HttpError, List<CompanyNewsItem>>>.new,
    );
    final result = await completer.future;
    return result.map((items) => items.take(limit).toList());
  }

  Future<void> _flush(_Batch batch) async {
    final tickers = batch.waiters.keys.toList();
    for (var i = 0; i < tickers.length; i += maxTickersPerCall) {
      final chunk = tickers.sublist(
        i,
        (i + maxTickersPerCall).clamp(0, tickers.length),
      );
      final response = await _client.get(
        'headlines',
        query: {
          'tickers': chunk.join(','),
          if (batch.from != null) 'from': _day(batch.from!),
          if (batch.to != null) 'to': _day(batch.to!),
        },
      );
      for (final t in chunk) {
        batch.waiters[t]!.complete(_resultFor(t, response));
      }
    }
  }

  Either<HttpError, List<CompanyNewsItem>> _resultFor(
    String ticker,
    EdgeResponse response,
  ) {
    if (response.planRequired) {
      return Left(HttpError(code: 'plan_required'));
    }
    if (!response.ok) {
      return Left(HttpError(code: 'headlines_${response.statusCode}'));
    }
    final byTicker = response.body!['by_ticker'];
    final raw = byTicker is Map ? byTicker[ticker] : null;
    if (raw is! List) return const Right([]);
    final items =
        raw
            .whereType<Map>()
            .map((h) => _parse(h, ticker))
            .whereType<CompanyNewsItem>()
            .toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return Right(items);
  }

  static CompanyNewsItem? _parse(Map raw, String ticker) {
    final title = '${raw['title'] ?? ''}'.trim();
    final url = '${raw['url'] ?? ''}'.trim();
    final published = DateTime.tryParse('${raw['published_at'] ?? ''}');
    if (title.isEmpty || !url.startsWith('http') || published == null) {
      return null;
    }
    return CompanyNewsItem(
      ticker: ticker,
      headline: title,
      // GDELT no trae bajada, y no se baja el texto del artículo.
      summary: '',
      url: url,
      source: '${raw['source'] ?? ''}',
      publishedAt: published.toUtc(),
      sourceDomain: raw['domain'] as String?,
    );
  }

  static String _day(DateTime d) {
    final u = d.toUtc();
    return '${u.year.toString().padLeft(4, '0')}-'
        '${u.month.toString().padLeft(2, '0')}-'
        '${u.day.toString().padLeft(2, '0')}';
  }
}

class _Batch {
  _Batch({this.from, this.to});

  final DateTime? from;
  final DateTime? to;
  final waiters =
      <String, Completer<Either<HttpError, List<CompanyNewsItem>>>>{};
}
