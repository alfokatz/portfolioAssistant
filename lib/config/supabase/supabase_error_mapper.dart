import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseErrorMapper {
  SupabaseErrorMapper._();

  static HttpError fromObject(Object error) {
    if (error is AuthException) {
      return HttpError(
        code: error.code ?? 'auth_error',
        message: error.message,
      );
    }
    if (error is PostgrestException) {
      return HttpError(
        code: error.code ?? 'database_error',
        message: error.message,
      );
    }
    return HttpError(
      code: 'unknown_error',
      message: error.toString(),
    );
  }
}
