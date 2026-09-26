/// Detecta si el mensaje del usuario es una consulta sobre noticias o causas
/// de movimientos de mercado.
bool isNewsQuery(String text) {
  final lower = text.toLowerCase();
  const keywords = [
    'noticia',
    'noticias',
    'news',
    'novedad',
    'novedades',
    'qué pasó',
    'que pasó',
    'que paso',
    'qué paso',
    'what happened',
    "what's happening",
    'whats happening',
    'recent events',
    'eventos recientes',
    'mercado hoy',
    'market today',
    'esta semana',
    'this week',
    'debería saber',
    'deberia saber',
    'should i know',
    'before investing',
    'antes de invertir',
    'headlines',
    'titulares',
    'últimas',
    'ultimas',
    'latest',
    'breaking',
    'actualidad',
    'qué está pasando',
    'que esta pasando',
    'what is happening',
    'por qué',
    'porque',
    'por que',
    'why',
    'motivo',
    'causa',
    'caída',
    'caida',
    'cayó',
    'cayo',
    'subió',
    'subio',
    'what caused',
    'reason for',
  ];

  return keywords.any(lower.contains);
}

/// Pedido EXPLÍCITO de noticias/eventos ("noticias de AAPL", "¿qué pasó con
/// NVDA?", "titulares de TSLA"). Es lo que se cobra y se gatea como consulta
/// de noticias (paywall Gold, peso de cuota 3).
///
/// [isNewsQuery] es más amplio a propósito — también cuenta frases de
/// tiempo o de causa ("esta semana", "por qué subió", "caída") para que
/// `ExploreNewsEnricher` traiga titulares cuando el plan lo permite. Usarlo
/// para gatear le ponía paywall a un Premium por "¿cómo está NVDA esta
/// semana?" y le cobraba triple a un Gold por la misma pregunta de precio.
bool isExplicitNewsRequest(String text) {
  final lower = text.toLowerCase();
  const keywords = [
    'noticia',
    'news',
    'novedad',
    'titulares',
    'headlines',
    'breaking',
    'actualidad',
    'qué pasó',
    'que pasó',
    'que paso',
    'qué paso',
    'qué está pasando',
    'que esta pasando',
    'what happened',
    "what's happening",
    'whats happening',
    'what is happening',
    'recent events',
    'eventos recientes',
  ];

  return keywords.any(lower.contains);
}
