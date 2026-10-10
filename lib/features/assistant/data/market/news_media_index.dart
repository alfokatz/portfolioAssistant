import 'package:portfolio_assistant/domain/entities/company_news_item.dart';

/// Lo que la card de noticias necesita de un artículo y el modelo NO:
/// la imagen de portada y el timestamp exacto.
class NewsMedia {
  const NewsMedia({
    required this.publishedAt,
    this.imageUrl,
    this.sourceDomain,
  });

  final DateTime publishedAt;
  final String? imageUrl;

  /// Dominio del medio: si no hay imagen, la card muestra su logo.
  final String? sourceDomain;
}

/// Índice en memoria `url del artículo → NewsMedia`, que llena
/// `NewsFetcher` cada vez que `get_news` devuelve titulares.
///
/// Las URLs de imagen son largas y el modelo no las necesita para
/// razonar: mandarlas costaría tokens en cada turno y abriría la puerta a
/// que invente una. El modelo solo copia la `url` del artículo al widget,
/// y la card busca acá la imagen y la hora de publicación.
class NewsMediaIndex {
  NewsMediaIndex({this.maxEntries = 200});

  /// Instancia de la app: el fetcher (capa de tools) y la card (capa de
  /// UI) viven en lugares distintos del árbol pero comparten la sesión.
  static final instance = NewsMediaIndex();

  final int maxEntries;
  // Map literal = LinkedHashMap: conserva orden de inserción (para el tope).
  final _byUrl = <String, NewsMedia>{};

  void record(CompanyNewsItem item) {
    if (item.url.isEmpty) return;
    _byUrl.remove(item.url);
    _byUrl[item.url] = NewsMedia(
      publishedAt: item.publishedAt,
      imageUrl: item.imageUrl,
      sourceDomain: item.sourceDomain,
    );
    // Tope por si la sesión es larga: se descartan los más viejos.
    while (_byUrl.length > maxEntries) {
      _byUrl.remove(_byUrl.keys.first);
    }
  }

  NewsMedia? lookup(String? url) =>
      url == null || url.isEmpty ? null : _byUrl[url];

  void clear() => _byUrl.clear();
}
