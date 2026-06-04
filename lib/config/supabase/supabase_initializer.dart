import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Inicializa el cliente global de Supabase desde variables `.env`.
class SupabaseInitializer {
  SupabaseInitializer._();

  static Future<void> initialize() async {
    final url = dotenv.env['SUPABASE_URL']?.trim();
    final anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim();

    if (url == null || url.isEmpty) {
      throw StateError('Falta SUPABASE_URL en el archivo .env del flavor activo.');
    }
    if (anonKey == null || anonKey.isEmpty) {
      throw StateError(
        'Falta SUPABASE_ANON_KEY en el archivo .env del flavor activo.',
      );
    }

    await Supabase.initialize(
      url: url,
      publishableKey: anonKey,
    );
  }
}
