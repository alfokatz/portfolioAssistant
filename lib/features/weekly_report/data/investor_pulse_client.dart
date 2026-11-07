import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/investor_pulse_item.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/report_week.dart';

/// Lee "qué dicen los super investors" de una semana desde la edge function
/// `investor-pulse` (caché compartida en el servidor).
///
/// Nunca lanza: `null` = no se pudo consultar; lista vacía = no hubo nada.
class InvestorPulseClient {
  InvestorPulseClient({
    Dio? dio,
    String? baseUrl,
    Future<String?> Function()? accessToken,
    String? anonKey,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 8),
               // El primer armado de la semana baja noticias y la SEC.
               receiveTimeout: const Duration(seconds: 30),
               validateStatus: (s) => s != null && s < 500,
             ),
           ),
       _baseUrl = baseUrl ?? _defaultBaseUrl(),
       _accessToken = accessToken ?? AiProxyConfig.supabaseAccessToken,
       _anonKey = anonKey ?? _env('SUPABASE_ANON_KEY');

  final Dio _dio;
  final String _baseUrl;
  final Future<String?> Function() _accessToken;
  final String? _anonKey;

  static String _defaultBaseUrl() {
    final supabase = _env('SUPABASE_URL') ?? '';
    return supabase.isEmpty ? '' : '$supabase/functions/v1/investor-pulse';
  }

  static String? _env(String name) {
    try {
      return dotenv.maybeGet(name)?.trim();
    } catch (_) {
      return null; // `.env` sin cargar (tests)
    }
  }

  Future<List<InvestorPulseItem>?> fetch(ReportWeek week) async {
    if (_baseUrl.isEmpty) return null;
    try {
      final token = await _accessToken();
      final response = await _dio.get<dynamic>(
        _baseUrl,
        queryParameters: {'week': week.key},
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            if (_anonKey != null) 'apikey': _anonKey,
          },
        ),
      );
      final data = response.data;
      if (response.statusCode != 200 || data is! Map) return null;
      final items = data['items'];
      if (items is! List) return null;
      return items
          .whereType<Map>()
          .map((raw) => InvestorPulseItem.tryParse(raw.cast<String, Object?>()))
          .whereType<InvestorPulseItem>()
          .toList();
    } catch (_) {
      return null;
    }
  }
}
