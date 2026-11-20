import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart'
    show HttpError;

abstract class BaseUseCase<Type, Params> {
  Future<Either<HttpError, Type>> call({required Params params});
}
