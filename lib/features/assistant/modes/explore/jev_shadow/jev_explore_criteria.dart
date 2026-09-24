/// Traducción de `explorePromptRules` (ver
/// `lib/features/assistant/modes/explore/explore_prompt_rules.dart`, 263
/// líneas de prosa) al formato `criteria` de una pregunta `choice` de
/// TypeSafe/Jev: un mapa opción -> rúbrica corta. Jev pide una descripción
/// concisa por opción, no un system prompt completo, así que esto NO es
/// una traducción 1:1 de las 263 líneas — es un resumen de las reglas
/// CRITICAL que distinguen cada widget.
///
/// Mismas 7 opciones que ya recibe el catálogo real de modo Explore (ver
/// `PortfolioQaCatalog._itemsFor(AssistantMode.explore)` en
/// `portfolio_qa_catalog.dart`).
const Map<String, String> jevExploreWidgetCriteria = {
  'QaAnswerText':
      'Respuesta en texto plano, sin widget de datos. Usar cuando: no hay '
      'ticker mencionado ni market_proxy_ticker en el snapshot (pregunta '
      'conceptual o de mercado en general); el ticker pedido tiene '
      'fetch_ok=false o explore_tickers está vacío; el usuario pide una '
      'métrica que este chat no tiene (volumen, open, high, low, market '
      'cap, P/E); o el dato de calendario de resultados / noticias pedido '
      'no está disponible (status empty, failed o locked).',
  'QaTickerSnapshot':
      'Snapshot de UN solo ticker SIN período explícito mencionado por el '
      'usuario: precio actual + cambio % de día/semana/mes. Nunca usar si '
      'el usuario menciona un período explícito (hoy/semana/mes/trimestre/'
      'año) — en ese caso corresponde QaTickerMove, no este. Tampoco usar '
      'si el usuario nombra 2 o 3 tickers a la vez — ahí corresponde '
      'QaMetricStrip.',
  'QaTickerMove':
      'Movimiento de UN solo ticker en un período EXPLÍCITO que el usuario '
      'menciona (hoy, esta semana, este mes, este trimestre, este año). '
      'Siempre gana sobre QaTickerSnapshot cuando hay un período explícito '
      'en el mensaje, incluso si la frase suena a pedido de snapshot '
      '("¿cómo está NVDA este mes?").',
  'QaMetricStrip':
      'Comparación de 2 o 3 tickers que el usuario nombra juntos en el '
      'mismo mensaje (ej. "¿cómo vienen hoy NVDA, AAPL y MSFT?", '
      '"comparame TSLA y AMD esta semana"). Nunca usar para un solo '
      'ticker.',
  'QaEarningsCalendar':
      'Preguntas sobre CUÁNDO una empresa reporta resultados próximamente '
      '(next_report), o sobre CÓMO le fue en su último reporte — EPS real '
      'vs. esperado (latest_result). Solo aplica si earnings_calendar_'
      'status es "ok" y el ticker tiene el dato pedido; si es "empty", '
      '"failed" o "locked", no corresponde este widget (va QaAnswerText).',
  'QaNewsSummary':
      'Preguntas explícitas por noticias, titulares o novedades recientes '
      'de un ticker. Solo aplica si news_enrichment es "ok" y news_sources '
      'no está vacío; si es "empty", "failed", "locked" o "skipped", no '
      'corresponde este widget (va QaAnswerText).',
  'QaTipBanner':
      'Nota educativa breve de una línea — casi nunca es la respuesta '
      'principal por sí sola, típicamente acompaña a QaAnswerText cuando '
      'el usuario pregunta el PORQUÉ de un movimiento de precio y no hay '
      'noticias verificadas disponibles, o cuando una función (noticias, '
      'calendario) está bloqueada por el plan del usuario en lugar de '
      'faltar el dato.',
};

/// El snapshot que arma `ExploreContextBuilder` NO incluye el mensaje
/// textual del usuario (solo datos de mercado ya resueltos) — sin decirle
/// esto a Jev explícitamente vía las instrucciones, y sin agregar el
/// mensaje al `state` (ver `JevShadowRunner._run`), Jev no tendría forma de
/// saber qué ticker/período/comparación pidió el usuario.
const String jevExploreWidgetQuestionInstructions =
    'Dado ASSISTANT_SNAPSHOT como estado (precios y cambios por ticker y '
    'período, calendario de resultados, noticias, encaje en el portfolio) '
    'y el mensaje del usuario en el campo user_message del mismo estado, '
    '¿qué widget de GenUI debería ser la respuesta PRINCIPAL de este turno '
    'en modo Explore?';
