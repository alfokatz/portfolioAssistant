import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/repositories/refresh_token_repository.dart'
    show RefreshTokenRepository;

class RefreshTokenRepositoryImpl implements RefreshTokenRepository {
  RefreshTokenRepositoryImpl();

  @override
  Future<Either<HttpError, String>> refreshToken() async {
    try {
      return right("");
    } on DioException catch (exception) {
      return left(HttpError.dioError(exception));
    } catch (exception) {
      return left(HttpError(code: "otro", message: "otro"));
    }
  }
}

final refreshTokenRepository = Provider<RefreshTokenRepository>(
  (ref) => RefreshTokenRepositoryImpl(),
);
