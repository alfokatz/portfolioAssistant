import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';

/// `Right([])` significa "se consultó bien, no hay noticias recientes".
/// `Left` significa que la consulta en sí falló (red, auth, etc.).
abstract class CompanyNewsRepository {
  Future<Either<HttpError, List<CompanyNewsItem>>> getRecentNews(
    String ticker, {
    int limit = 3,
  });
}
