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
}
