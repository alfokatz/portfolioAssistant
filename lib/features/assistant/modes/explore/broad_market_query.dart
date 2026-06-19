/// Detecta preguntas genéricas sobre el mercado sin ticker explícito.
bool isBroadMarketQuery(String text) {
  final lower = text.toLowerCase();
  const keywords = [
    'mercado',
    'market',
    'bolsa',
    'índice',
    'indice',
    'index',
    's&p',
    'sp500',
    's&p 500',
    'wall street',
    'acciones en general',
    'bursátil',
    'bursatil',
  ];

  return keywords.any(lower.contains);
}

/// Ticker usado como referencia cuando el usuario pregunta por "el mercado".
const String broadMarketProxyTicker = 'SPY';
