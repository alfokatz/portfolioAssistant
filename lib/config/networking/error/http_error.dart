import 'package:dio/dio.dart';
import 'package:portfolio_assistant/config/networking/error/error_type.dart';

class HttpError {
  static const Map<int, String> httpErrors = {
    401: 'unauthorized',
    403: 'forbidden',
    404: 'not_found',
    408: 'request_timeout',
    500: 'internal_server_error',
    502: 'bad_gateway',
    503: 'service_unavailable',
    504: 'gateway_timeout',
  };

  late String code;

  String? errorTitle;

  String? message;

  String? type;

  String? actionBtnText;

  HttpError({
    required this.code,
    this.errorTitle,
    this.message,
    this.type,
    this.actionBtnText,
  });

  factory HttpError.fromJson(Map<String, dynamic> json) {
    return HttpError(
      code: json["code"] ?? 'unknown',
      errorTitle: json["error_title"],
      message: json["error_msg"],
      type: json["type"],
      actionBtnText: json["action_btn_text"],
    );
  }

  HttpError.dioError(DioException error) {
    if (error.response != null &&
        error.response!.data is Map<String, dynamic> &&
        (error.response!.data["error_msg"] != null ||
            error.response!.data["error_title"] != null)) {
      try {
        final parsedError = HttpError.fromJson(
          error.response!.data as Map<String, dynamic>,
        );
        code = parsedError.code;
        errorTitle = parsedError.errorTitle;
        message = parsedError.message;
        type = parsedError.type;
        actionBtnText = parsedError.actionBtnText;
        return;
        // ignore: empty_catches
      } catch (e) {}
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        _setLocalizationKeys(ErrorType.connectionTimeout);
        break;
      case DioExceptionType.receiveTimeout:
        _setLocalizationKeys(ErrorType.receiveTimeout);
        break;
      case DioExceptionType.sendTimeout:
        _setLocalizationKeys(ErrorType.sendTimeout);
        break;
      case DioExceptionType.cancel:
        _setLocalizationKeys(ErrorType.cancelled);
        break;
      case DioExceptionType.badResponse:
        code = httpErrors[error.response?.statusCode] ?? 'unknown';
        _setLocalizationKeys(ErrorType.badResponse);
        break;
      case DioExceptionType.badCertificate:
        _setLocalizationKeys(ErrorType.sslError);
        break;
      case DioExceptionType.connectionError:
        _setLocalizationKeys(ErrorType.connectionError);
        break;
      case DioExceptionType.unknown:
        _setLocalizationKeys(ErrorType.unknown);
        break;
    }
  }

  void _setLocalizationKeys(ErrorType errorType) {
    final keys = errorLocalizationKeys[errorType]!;
    code = errorType.toString();
    errorTitle = keys['title'];
    message = keys['message'];
  }

  @override
  String toString() {
    return 'HttpError{code: $code, errorTitle: $errorTitle, message: $message, type: $type, actionBtnText: $actionBtnText}';
  }
}
