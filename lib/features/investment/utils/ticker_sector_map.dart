/// Mapeo estático ticker → sector para reglas de diversificación.
abstract final class TickerSectorMap {
  static const _map = <String, String>{
    'AAPL': 'Technology',
    'MSFT': 'Technology',
    'GOOGL': 'Technology',
    'GOOG': 'Technology',
    'META': 'Technology',
    'NVDA': 'Technology',
    'AMD': 'Technology',
    'INTC': 'Technology',
    'AMZN': 'Technology',
    'TSLA': 'Technology',
    'NFLX': 'Technology',
    'CRM': 'Technology',
    'ORCL': 'Technology',
    'ADBE': 'Technology',
    'QQQ': 'Technology',
    'XLK': 'Technology',
    'JPM': 'Financials',
    'BAC': 'Financials',
    'WFC': 'Financials',
    'GS': 'Financials',
    'MS': 'Financials',
    'V': 'Financials',
    'MA': 'Financials',
    'XLF': 'Financials',
    'JNJ': 'Healthcare',
    'PFE': 'Healthcare',
    'UNH': 'Healthcare',
    'MRK': 'Healthcare',
    'ABBV': 'Healthcare',
    'XLV': 'Healthcare',
    'XOM': 'Energy',
    'CVX': 'Energy',
    'COP': 'Energy',
    'XLE': 'Energy',
    'KO': 'Consumer',
    'PEP': 'Consumer',
    'WMT': 'Consumer',
    'PG': 'Consumer',
    'MCD': 'Consumer',
    'XLY': 'Consumer',
    'VTI': 'Broad Market',
    'VOO': 'Broad Market',
    'SPY': 'Broad Market',
    'IVV': 'Broad Market',
    'BND': 'Fixed Income',
    'AGG': 'Fixed Income',
    'TLT': 'Fixed Income',
  };

  static String sectorFor(String ticker) {
    final key = ticker.trim().toUpperCase();
    return _map[key] ?? 'Other';
  }

  static Map<String, double> sectorWeightsFromTickers(
    Map<String, double> tickerWeights,
  ) {
    final sectors = <String, double>{};
    for (final entry in tickerWeights.entries) {
      final sector = sectorFor(entry.key);
      sectors[sector] = (sectors[sector] ?? 0) + entry.value;
    }
    return sectors;
  }
}
