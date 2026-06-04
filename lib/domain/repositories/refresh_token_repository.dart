import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';

abstract class RefreshTokenRepository {
  Future<Either<HttpError, String>> refreshToken();
}
