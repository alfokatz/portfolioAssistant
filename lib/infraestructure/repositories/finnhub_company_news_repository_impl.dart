import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/repositories/company_news_repository.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/finnhub_http_client.dart';

/// Nunca lanza: ante red/timeout/401/datos vacíos devuelve `Left`/`Right([])`
/// según corresponda, nunca deja escapar una excepción — mismo contrato que
/// `FinnhubEarningsCalendarRepositoryImpl`.
class FinnhubCompanyNewsRepositoryImpl implements CompanyNewsRepository {
  FinnhubCompanyNewsRepositoryImpl({FinnhubHttpClient? client})
    : _client = client ?? FinnhubHttpClient();

  final FinnhubHttpClient _client;

  @override
  Future<Either<HttpError, List<CompanyNewsItem>>> getRecentNews(
    String ticker, {
    int limit = 3,
    DateTime? from,
    DateTime? to,
  }) async {
    if (!_client.isConfigured) {
      return Left(
        HttpError(
          code: 'finnhub_unavailable',
          message: 'Proxy de Finnhub no configurado',
        ),
      );
    }

    final windowed = from != null && to != null;
    // Finnhub toma `to` inclusive (días): el `to` exclusivo del contrato es
    // el día anterior.
    final rangeTo =
        windowed ? to.subtract(const Duration(days: 1)) : DateTime.now();
    final rangeFrom =
        windowed ? from : rangeTo.subtract(const Duration(days: 14));
    final upperTicker = ticker.toUpperCase();

    try {
      final response = await _client.get(
        '/company-news',
        queryParameters: {
          'symbol': upperTicker,
          'from': FinnhubHttpClient.formatDate(rangeFrom),
          'to': FinnhubHttpClient.formatDate(rangeTo),
        },
      );

      if (response.statusCode != 200) {
        return Left(HttpError(code: 'finnhub_error_${response.statusCode}'));
      }

      final data = response.data;
      if (data is! List) return const Right([]);

      final items =
          data
              .whereType<Map>()
              .map((raw) => _parseItem(raw, upperTicker))
              .whereType<CompanyNewsItem>()
              .toList()
            ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      if (windowed) {
        items.removeWhere(
          (i) => i.publishedAt.isBefore(from) || !i.publishedAt.isBefore(to),
        );
      }

      return Right(items.take(limit).toList());
    } on DioException catch (e) {
      return Left(HttpError(code: 'network_error', message: e.message));
    } catch (_) {
      return Left(HttpError(code: 'unknown'));
    }
  }

  CompanyNewsItem? _parseItem(Map raw, String ticker) {
    final headline = raw['headline'] as String?;
    final url = raw['url'] as String?;
    final datetimeRaw = raw['datetime'];
    if (headline == null ||
        headline.isEmpty ||
        url == null ||
        datetimeRaw is! num) {
      return null;
    }

    return CompanyNewsItem(
      ticker: ticker,
      headline: headline,
      summary: (raw['summary'] as String?) ?? '',
      url: url,
      source: (raw['source'] as String?) ?? '',
      publishedAt: DateTime.fromMillisecondsSinceEpoch(
        datetimeRaw.toInt() * 1000,
        isUtc: true,
      ),
      imageUrl: _imageUrl(raw['image']),
    );
  }

  /// Finnhub manda `""` cuando no hay imagen, y algunos medios publican
  /// URLs `http://` que iOS bloquea: solo se aceptan `https` no vacías.
  static String? _imageUrl(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.startsWith('https://') ? trimmed : null;
  }
}
