/// Un tema del catálogo cerrado (`news_topics`). Los rótulos vienen de la
/// base, en los dos idiomas.
class NewsTopic {
  const NewsTopic({
    required this.id,
    required this.kind,
    required this.labelEs,
    required this.labelEn,
    this.defaultGlobal = false,
    this.autoMarkets = const [],
    this.autoAssetClasses = const [],
    this.region = 'global',
    this.sort = 100,
  });

  final String id;
  final String kind;
  final String labelEs;
  final String labelEn;
  final bool defaultGlobal;

  /// Mercados de la cartera que lo siguen por defecto (`US`, `.BA`, `.MC`…).
  final List<String> autoMarkets;
  final List<String> autoAssetClasses;
  final String region;
  final int sort;

  String label(String language) => language == 'en' ? labelEn : labelEs;

  /// ¿Es un tema que el servidor le arma por defecto con estos [markets]?
  /// (La clase de activo no se puede saber acá: solo mercado.)
  bool isDefaultFor(Set<String> markets) =>
      defaultGlobal || autoMarkets.any(markets.contains);

  static NewsTopic? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final es = raw['label_es'];
    final en = raw['label_en'];
    if (id is! String || es is! String || en is! String) return null;
    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : const [];
    return NewsTopic(
      id: id,
      kind: raw['kind'] is String ? raw['kind'] as String : 'macro',
      labelEs: es,
      labelEn: en,
      defaultGlobal: raw['default_global'] == true,
      autoMarkets: strings(raw['auto_markets']),
      autoAssetClasses: strings(raw['auto_asset_classes']),
      region: raw['region'] is String ? raw['region'] as String : 'global',
      sort: raw['sort'] is num ? (raw['sort'] as num).toInt() : 100,
    );
  }
}

/// Un medio de la allowlist (`news_source_allowlist`).
class NewsSource {
  const NewsSource({
    required this.domain,
    required this.name,
    this.lang = 'en',
    this.region = 'global',
    this.kind = 'media',
  });

  final String domain;
  final String name;
  final String lang;
  final String region;

  /// `media` o `official` (fuentes oficiales: no se eligen).
  final String kind;

  static NewsSource? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final domain = raw['domain'];
    final name = raw['name'];
    if (domain is! String || name is! String) return null;
    return NewsSource(
      domain: domain,
      name: name,
      lang: raw['lang'] is String ? raw['lang'] as String : 'en',
      region: raw['region'] is String ? raw['region'] as String : 'global',
      kind: raw['kind'] is String ? raw['kind'] as String : 'media',
    );
  }
}

/// Qué hace el usuario con un medio: lo prefiere (sale primero) o lo
/// silencia (no aparece). Sin preferencia, no hay fila.
enum SourcePreference {
  prefer,
  mute;

  static SourcePreference? fromWire(Object? v) => switch (v) {
    'prefer' => SourcePreference.prefer,
    'mute' => SourcePreference.mute,
    _ => null,
  };
}

/// Topes de la base (`topic_limit_reached`, `source_limit_reached`).
abstract final class NewsPreferencesLimits {
  static const topics = 12;
  static const sourcesPerList = 10;
}

/// El mercado de un ticker por su sufijo de bolsa: `NVDA` → `US`,
/// `GGAL.BA` → `.BA`. Es una regla de formato, no una lista de tickers.
String marketOfTicker(String ticker) {
  final i = ticker.lastIndexOf('.');
  if (i <= 0 || i == ticker.length - 1) return 'US';
  return '.${ticker.substring(i + 1).toUpperCase()}';
}
