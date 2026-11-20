/// Identidad visual mínima de una compañía para las cards del asistente:
/// nombre legible y logo. Ambos opcionales — los ETFs y muchos tickers
/// chicos no tienen perfil en Finnhub, y la UI cae a un monograma.
class CompanyBrand {
  const CompanyBrand({required this.ticker, this.name, this.logoUrl});

  final String ticker;
  final String? name;
  final String? logoUrl;
}
