import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_fundamentals.dart';

/// `Right(null)` significa "se consultó bien, no hay datos de fundamentals
/// para ese ticker" (ej. símbolo inválido, o Finnhub sin cobertura para esa
/// plaza). `Left` significa que la consulta en sí falló (red, auth, etc.) —
/// la misma distinción absence-vs-error que ya usa `EarningsCalendarRepository`.
abstract class CompanyFundamentalsRepository {
  Future<Either<HttpError, CompanyFundamentals?>> getFundamentals(
    String ticker,
  );
}
