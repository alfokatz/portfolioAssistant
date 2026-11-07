/// Un titular de noticias reciente sobre un ticker.
class CompanyNewsItem {
  const CompanyNewsItem({
    required this.ticker,
    required this.headline,
    required this.summary,
    required this.url,
    required this.source,
    required this.publishedAt,
    this.imageUrl,
    this.sourceDomain,
  });

  final String ticker;
  final String headline;
  final String summary;
  final String url;
  final String source;
  final DateTime publishedAt;

  /// Imagen de portada que publica el medio. Solo la usa la card (vía
  /// `NewsMediaIndex`) — nunca se le manda al modelo.
  final String? imageUrl;

  /// Dominio del medio ("reuters.com"), para mostrar su logo en la card
  /// cuando la nota no trae imagen. Tampoco se le manda al modelo.
  final String? sourceDomain;
}
