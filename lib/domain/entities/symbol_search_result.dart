/// Un resultado de Finnhub `/search`: candidato de ticker para un nombre de
/// compañía en texto libre (ej. "Apple" -&gt; `AAPL`).
class SymbolSearchResult {
  const SymbolSearchResult({
    required this.symbol,
    required this.description,
    required this.type,
  });

  final String symbol;
  final String description;

  /// Tal cual lo devuelve Finnhub (ej. "Common Stock", "ETP"), sin normalizar.
  final String type;
}
