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
  }) async {
    if (!_client.hasApiKey) {
      return Left(
        HttpError(
          code: 'missing_api_key',
          message: 'FINNHUB_API_KEY no configurada',
        ),
      );
    }

    final to = DateTime.now();
    final from = to.subtract(const Duration(days: 14));
    final upperTicker = ticker.toUpperCase();

    try {
      final response = await _client.get(
        '/company-news',
        queryParameters: {
          'symbol': upperTicker,
          'from': FinnhubHttpClient.formatDate(from),
          'to': FinnhubHttpClient.formatDate(to),
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
    );
  }
}
