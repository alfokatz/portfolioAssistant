import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';

/// `Right([])` significa "se consultó bien, no hay noticias recientes".
/// `Left` significa que la consulta en sí falló (red, auth, etc.).
abstract class CompanyNewsRepository {
  /// Sin [from]/[to]: lo reciente (la ventana propia de cada fuente). Con
  /// ambos: solo notas publicadas en `[from, to)` — días calendario; lo usa
  /// el informe semanal, que cubre una semana cerrada aunque se genere días
  /// después.
  Future<Either<HttpError, List<CompanyNewsItem>>> getRecentNews(
    String ticker, {
    int limit = 3,
    DateTime? from,
    DateTime? to,
  });
}
