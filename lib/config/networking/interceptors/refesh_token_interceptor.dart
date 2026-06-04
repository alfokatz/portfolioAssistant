import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart'
    show HttpError;
import 'package:portfolio_assistant/config/networking/http_client.dart';
import 'package:portfolio_assistant/config/networking/interceptors/header_interceptor.dart';
import 'package:portfolio_assistant/domain/repositories/refresh_token_repository.dart'
    show RefreshTokenRepository;
import 'package:portfolio_assistant/infraestructure/repositories/refresh_token_repository_impl.dart';

class RefreshTokenInterceptor extends InterceptorsWrapper {
  final List<int> _responseCodeRefreshToken = [401, 403];
  final HttpClient client;
  final RefreshTokenRepository refreshTokenRepository;
  final HeaderInterceptor headerInterceptor;

  RefreshTokenInterceptor({
    required this.client,
    required this.refreshTokenRepository,
    required this.headerInterceptor,
  });

  @override
  Future<void> onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    if (_requireRefreshToken(error.response?.statusCode)) {
      final RequestOptions requestOptions = error.requestOptions;

      final Either<HttpError, String> result =
          await refreshTokenRepository.refreshToken();

      result.fold(
        (errorService) {
          handler.reject(error);
        },
        (success) async {
          final options = _getOptions(
            serviceMethod: requestOptions.method,
            token: success,
          );

          try {
            final response = await client.dio.request<Map<String, dynamic>>(
              requestOptions.path,
              options: options,
              data: requestOptions.data,
              queryParameters: requestOptions.queryParameters,
            );

            return handler.resolve(response);
          } catch (e) {
            return handler.reject(DioException(requestOptions: requestOptions));
          }
        },
      );
    } else {
      return handler.next(error);
    }
  }

  Options _getOptions({required String serviceMethod, required String token}) {
    final options = Options(method: serviceMethod);
    options.headers = headerInterceptor.getHeaders(token: token);
    return options;
  }

  bool _requireRefreshToken(int? statusCode) =>
      _responseCodeRefreshToken.contains(statusCode);
}

final refreshTokenInterceptorProvider = Provider<RefreshTokenInterceptor>(
  (ref) => RefreshTokenInterceptor(
    client: ref.read(httpClientProvider),
    refreshTokenRepository: ref.watch(refreshTokenRepository),
    headerInterceptor: ref.watch(headerInterceptorProvider),
  ),
);
