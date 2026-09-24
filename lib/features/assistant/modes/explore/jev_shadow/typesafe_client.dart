import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/jev_shadow/jev_shadow_config.dart';

/// Respuesta de una pregunta `choice` de TypeSafe/Jev.
class TypeSafeChoiceAnswer {
  TypeSafeChoiceAnswer({
    required this.choice,
    required this.confidence,
    required this.probabilities,
    required this.latency,
  });

  final String choice;
  final double confidence;
  final Map<String, double> probabilities;
  final Duration latency;
}

/// Cliente crudo para la API de TypeSafe (`POST /v1/systemone`), mismo
/// patrón que `FinnhubHttpClient`: solo arma la request y traduce fallas a
/// `Either<HttpError, T>`, nunca lanza. Usado exclusivamente por el
/// experimento de shadow-mode de Jev en modo Explore — ver
/// `JevShadowRunner`. No hay SDK oficial de Dart todavía (solo paquetes de
/// comunidad de días de antigüedad), de ahí Dio crudo en vez de una
/// dependencia externa.
class TypeSafeClient {
  TypeSafeClient({Dio? dio, String? apiKey})
    : _dio = dio ?? _createDio(),
      _apiKey = apiKey ?? JevShadowConfig.apiKey;

  final Dio _dio;
  final String _apiKey;

  static const baseUrl = 'https://api.typesafe.ai/v1/systemone';

  bool get hasApiKey => _apiKey.isNotEmpty;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        // Jev documenta 70-500ms de latencia típica; 5s es margen amplio
        // para no cortar de más, sin dejar un shadow call colgado mucho
        // tiempo (esto corre fire-and-forget, nunca bloquea al usuario,
        // pero igual no debería acumular llamadas colgadas indefinidamente).
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        validateStatus: (status) => status != null && status < 500,
      ),
    );
  }

  /// Evalúa una única pregunta `choice` de nombre [questionName] contra
  /// [state] (el mismo snapshot JSON de `ExploreContextBuilder`, con el
  /// mensaje del usuario agregado — ver `JevShadowRunner`), usando
  /// [criteria] como catálogo cerrado de opciones.
  Future<Either<HttpError, TypeSafeChoiceAnswer>> chooseWidget({
    required Object state,
    required Map<String, String?> criteria,
    required String instructions,
    String questionName = 'widget',
  }) async {
    if (!hasApiKey) {
      return Left(
        HttpError(
          code: 'missing_api_key',
          message: 'TYPESAFE_API_KEY no configurada',
        ),
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final response = await _dio.post<dynamic>(
        baseUrl,
        data: {
          'state': state,
          'questions': {
            questionName: {
              'type': 'choice',
              'instructions': instructions,
              'criteria': criteria,
            },
          },
        },
        options: Options(
          contentType: Headers.jsonContentType,
          headers: {'Authorization': 'Bearer $_apiKey'},
        ),
      );
      stopwatch.stop();

      if (response.statusCode != 200) {
        return Left(HttpError(code: 'typesafe_error_${response.statusCode}'));
      }

      final body = response.data;
      Object? answer;
      if (body is Map) {
        final answers = body['answers'];
        if (answers is Map) answer = answers[questionName];
      }
      if (answer is! Map || answer['choice'] is! String) {
        return Left(HttpError(code: 'malformed_response'));
      }

      final rawProbabilities = answer['probabilities'];
      final probabilities = <String, double>{
        if (rawProbabilities is Map)
          for (final entry in rawProbabilities.entries)
            if (entry.value is num)
              entry.key as String: (entry.value as num).toDouble(),
      };

      return Right(
        TypeSafeChoiceAnswer(
          choice: answer['choice'] as String,
          confidence: (answer['confidence'] as num?)?.toDouble() ?? 0,
          probabilities: probabilities,
          latency: stopwatch.elapsed,
        ),
      );
    } on DioException catch (e) {
      stopwatch.stop();
      return Left(HttpError(code: 'network_error', message: e.message));
    } catch (_) {
      stopwatch.stop();
      return Left(HttpError(code: 'unknown'));
    }
  }
}

final typeSafeClientProvider = Provider<TypeSafeClient>(
  (ref) => TypeSafeClient(),
);
