import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/symbol_search_result.dart';

/// `Right([])` = se consultó bien, no hay matches para `query`. `Left` = la
/// consulta en sí falló (red, auth, key faltante) — mismo contrato que
/// `CompanyNewsRepository`/`EarningsCalendarRepository`.
abstract class SymbolSearchRepository {
  Future<Either<HttpError, List<SymbolSearchResult>>> search(String query);
}
