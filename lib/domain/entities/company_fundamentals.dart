/// Fundamentales de una compañía: datos de perfil (`/stock/profile2`) +
/// métricas de valuación/rentabilidad/dividendo (`/stock/metric?metric=all`)
/// de Finnhub, ya combinados en un único snapshot por ticker.
///
/// Es un subconjunto curado, no el objeto crudo de Finnhub: el endpoint de
/// métricas devuelve 100+ campos, muchos casi duplicados entre sí (ej.
/// `peBasicExclExtraTTM`/`peExclExtraTTM`/`peInclExtraTTM` suelen traer el
/// mismo valor) y una serie histórica completa (`series.annual`/`quarterly`,
/// desde 1985 en algunos casos) que no es un "dato actual" y no hace falta
/// para responder preguntas de fundamentals de hoy. Elegir un campo por
/// categoría evita que el modelo tenga que decidir entre variantes casi
/// idénticas, y evita mandar la serie histórica completa en cada snapshot.
///
/// UNIDADES — importante para no mostrar un número mal escalado:
/// - [marketCapitalization] y [sharesOutstanding] vienen de Finnhub en
///   MILLONES (ej. `4977637.06` = ~$4.98 billones/trillion USD).
/// - [averageVolume10Day] viene en MILLONES de acciones/día.
/// - [dividendYieldIndicatedAnnual] y los márgenes/ROE/ROA/payout YA están
///   expresados en porcentaje (ej. `0.505` significa 0,505%, no 50%) — NO
///   multiplicar por 100 al mostrarlos.
class CompanyFundamentals {
  const CompanyFundamentals({
    required this.ticker,
    this.companyName,
    this.industry,
    this.exchange,
    this.marketCapitalization,
    this.sharesOutstanding,
    this.peTTM,
    this.forwardPE,
    this.pb,
    this.psTTM,
    this.evEbitdaTTM,
    this.pegTTM,
    this.beta,
    this.roeTTM,
    this.roaTTM,
    this.grossMarginTTM,
    this.operatingMarginTTM,
    this.netMarginTTM,
    this.epsTTM,
    this.epsGrowthTTMYoy,
    this.bookValuePerShareQuarterly,
    this.revenuePerShareTTM,
    this.dividendYieldIndicatedAnnual,
    this.dividendPerShareTTM,
    this.payoutRatioTTM,
    this.week52High,
    this.week52Low,
    this.week52PriceReturnDaily,
    this.averageVolume10Day,
  });

  final String ticker;

  // --- Perfil (/stock/profile2) ---
  final String? companyName;
  final String? industry;
  final String? exchange;

  /// En millones de USD (u otra moneda de reporte).
  final double? marketCapitalization;

  /// En millones de acciones.
  final double? sharesOutstanding;

  // --- Valuación ---
  final double? peTTM;
  final double? forwardPE;
  final double? pb;
  final double? psTTM;
  final double? evEbitdaTTM;
  final double? pegTTM;
  final double? beta;

  // --- Rentabilidad (todos en %) ---
  final double? roeTTM;
  final double? roaTTM;
  final double? grossMarginTTM;
  final double? operatingMarginTTM;
  final double? netMarginTTM;

  // --- Por acción ---
  final double? epsTTM;

  /// Crecimiento interanual de EPS TTM, en %.
  final double? epsGrowthTTMYoy;
  final double? bookValuePerShareQuarterly;
  final double? revenuePerShareTTM;

  // --- Dividendo ---
  /// Yield anualizado indicado, YA en % (ej. 0.51 = 0,51%).
  final double? dividendYieldIndicatedAnnual;
  final double? dividendPerShareTTM;

  /// Payout ratio TTM, en %.
  final double? payoutRatioTTM;

  // --- Trading / rango ---
  final double? week52High;
  final double? week52Low;

  /// Retorno de precio a 52 semanas, en %.
  final double? week52PriceReturnDaily;

  /// Volumen promedio de 10 días, en millones de acciones.
  final double? averageVolume10Day;
}
