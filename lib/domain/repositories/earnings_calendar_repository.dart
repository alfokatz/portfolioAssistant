import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/earnings_calendar_entry.dart';
import 'package:portfolio_assistant/domain/entities/earnings_report_result.dart';

/// `Right(null)` significa "se consultó bien, no hay dato para ese ticker"
/// (ej. sin reporte próximo programado). `Left` significa que la consulta
/// en sí falló (red, auth, etc.) — la misma distinción absence-vs-error que
/// ya usa `QuoteRepository`.
abstract class EarningsCalendarRepository {
  Future<Either<HttpError, EarningsCalendarEntry?>> getNextEarningsDate(
    String ticker,
  );

  Future<Either<HttpError, EarningsReportResult?>> getLatestEarningsResult(
    String ticker,
  );
}
