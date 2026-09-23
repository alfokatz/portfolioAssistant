import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Cliente HTTP compartido para Finnhub (calendario de resultados +
/// noticias por ticker). Solo arma la request; los repos que lo usan son
/// responsables de convertir cualquier `DioException`/error a
/// `Either<HttpError, T>` — este cliente no interpreta el body.
class FinnhubHttpClient {
  FinnhubHttpClient({Dio? dio, String? apiKey})
    : _dio = dio ?? _createDio(),
      _apiKey = apiKey ?? dotenv.env['FINNHUB_API_KEY'] ?? '';

  final Dio _dio;
  final String _apiKey;

  static const baseUrl = 'https://finnhub.io/api/v1';

  bool get hasApiKey => _apiKey.isNotEmpty;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (status) => status != null && status < 500,
      ),
    );
  }

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _dio.get<dynamic>(
      '$baseUrl$path',
      queryParameters: {...?queryParameters, 'token': _apiKey},
    );
  }

  /// Formato `YYYY-MM-DD` que esperan los endpoints `from`/`to` de Finnhub.
  static String formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
