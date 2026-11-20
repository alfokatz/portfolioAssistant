import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// De dónde salen noticias, resultados y fundamentals. Lo decide el
/// servidor (`app_config.news_provider`) para poder volver atrás sin
/// publicar la app:
/// - [legacy]: Google News RSS + Finnhub (sin uso comercial);
/// - [v2]: SEC EDGAR + búsqueda web de OpenAI + GDELT, todo vía edge
///   functions que validan el plan en el servidor.
enum NewsProvider {
  legacy,
  v2;

  static NewsProvider parse(Object? value) =>
      value is Map && value['provider'] == 'v2' ? v2 : legacy;
}

/// Lee el interruptor una vez cada [ttl]. Falla cerrado a [NewsProvider.legacy]
/// (sin red o sin la fila, nada cambia respecto de hoy).
class NewsProviderConfig {
  NewsProviderConfig({
    Future<Object?> Function()? read,
    this.ttl = const Duration(minutes: 10),
  }) : _read = read ?? _readFromSupabase;

  static final instance = NewsProviderConfig();

  final Future<Object?> Function() _read;
  final Duration ttl;

  NewsProvider? _value;
  DateTime? _readAt;
  Future<NewsProvider>? _inFlight;

  /// El último valor leído (o [NewsProvider.legacy] si nunca se leyó).
  NewsProvider get current => _value ?? NewsProvider.legacy;

  Future<NewsProvider> load() {
    final readAt = _readAt;
    if (_value != null &&
        readAt != null &&
        DateTime.now().difference(readAt) < ttl) {
      return Future.value(_value);
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<NewsProvider> _fetch() async {
    try {
      final value = NewsProvider.parse(
        await _read().timeout(const Duration(seconds: 4)),
      );
      _value = value;
      _readAt = DateTime.now();
      return value;
    } catch (e) {
      if (kDebugMode) debugPrint('[NewsProvider] using $current: $e');
      return current;
    }
  }

  static Future<Object?> _readFromSupabase() async {
    final row =
        await Supabase.instance.client
            .from('app_config')
            .select('value')
            .eq('key', 'news_provider')
            .maybeSingle();
    return row?['value'];
  }
}
