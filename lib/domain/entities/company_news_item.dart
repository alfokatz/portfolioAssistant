/// Un titular de noticias reciente sobre un ticker.
class CompanyNewsItem {
  const CompanyNewsItem({
    required this.ticker,
    required this.headline,
    required this.summary,
    required this.url,
    required this.source,
    required this.publishedAt,
  });

  final String ticker;
  final String headline;
  final String summary;
  final String url;
  final String source;
  final DateTime publishedAt;
}
