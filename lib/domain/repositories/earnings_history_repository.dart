import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/earnings_surprise.dart';

/// Historial de EPS real vs. esperado por trimestre. `Right([])` = sin
/// historial para ese ticker; `Left` = la consulta falló.
abstract class EarningsHistoryRepository {
  /// Más reciente primero.
  Future<Either<HttpError, List<EarningsSurprise>>> getEpsHistory(
    String ticker,
  );
}
