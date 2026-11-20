/// Las pantallas desde donde se puede abrir Porty con contexto.
enum PortyScreen {
  positionDetail('position_detail'),
  closedPosition('closed_position'),
  goals('goals'),
  goalDetail('goal_detail'),
  watchlist('watchlist'),
  allocation('allocation_plan'),
  weeklyReport('weekly_report'),

  /// El brief diario (el pie "Preguntale a Porty").
  dailyBrief('daily_brief'),

  /// Una noticia del brief, el feed o un tema ("¿Cómo me afecta?", "Qué dice
  /// cada medio"): lo que se sabe de ella viaja en [PortyScreenContext.news].
  newsItem('news_item'),

  /// El primer diagnóstico de la cartera (lo que Porty vio al cargarla).
  diagnosis('portfolio_diagnosis');

  const PortyScreen(this.briefValue);

  /// Cómo viaja en `screen_context.screen` del brief.
  final String briefValue;
}

/// La noticia desde la que se abrió Porty: solo lo que la pantalla ya tiene
/// (el titular y su medio), nunca el cuerpo. Es texto de terceros: el modelo
/// lo lee como dato, no como instrucción (ver `newsContextGuidance`).
class PortyNewsItem {
  const PortyNewsItem({
    required this.title,
    this.source,
    this.url,
    this.publishedAt,
    this.ticker,
    this.topicId,
  });

  final String title;

  /// El medio ("Reuters").
  final String? source;
  final String? url;
  final DateTime? publishedAt;

  /// El ticker de la noticia, si es de una posición o de la watchlist.
  final String? ticker;

  /// El id del tema del catálogo (`news_topics.id`), si es de un tema: lo que
  /// `compare_sources` recibe como `topic`.
  final String? topicId;

  /// Tope del titular en el brief: un titular largo no tiene por qué comerse
  /// el contexto fijado.
  static const maxTitleChars = 240;

  Map<String, Object?> toBrief() => {
    'title':
        title.length > maxTitleChars
            ? title.substring(0, maxTitleChars)
            : title,
    if (source case final s? when s.isNotEmpty) 'source': s,
    if (url case final u? when u.startsWith('https://')) 'url': u,
    if (publishedAt case final d?) 'published_at': d.toUtc().toIso8601String(),
    if (ticker case final t? when t.isNotEmpty) 'ticker': t.toUpperCase(),
    if (topicId case final t? when t.isNotEmpty) 'topic_id': t,
  };
}

/// Lo que el usuario estaba mirando cuando abrió Porty: la pantalla y, si
/// es de algo puntual, qué (un ticker, una meta). Viaja en el brief del
/// turno (`screen_context`) para que "¿esto está bien?" o "¿por qué bajó?"
/// se entiendan sin nombrar nada.
class PortyScreenContext {
  const PortyScreenContext(
    this.screen, {
    this.ticker,
    this.goalLabel,
    this.news,
  });

  const PortyScreenContext.position(String ticker)
    : this(PortyScreen.positionDetail, ticker: ticker);

  const PortyScreenContext.newsItem(PortyNewsItem news)
    : this(PortyScreen.newsItem, news: news);

  final PortyScreen screen;
  final String? ticker;

  /// El nombre de la meta, tal como la guardó el usuario.
  final String? goalLabel;

  /// La noticia, si el chat se abrió desde una ([PortyScreen.newsItem]).
  final PortyNewsItem? news;

  /// Cuántos turnos sigue valiendo después de abrir el chat: pasado eso, la
  /// conversación ya es sobre otra cosa y "esto" no es la pantalla de antes.
  static const maxTurns = 3;

  /// El bloque `screen_context` del brief. [turnsAgo] = turnos desde que se
  /// abrió el chat desde esa pantalla (0 = la pregunta de ahora).
  Map<String, Object?> toBrief({required int turnsAgo}) => {
    'screen': screen.briefValue,
    if (ticker case final t?) 'ticker': t.toUpperCase(),
    if (goalLabel case final g?) 'goal': g,
    if (news case final n?) 'news': n.toBrief(),
    'turns_ago': turnsAgo,
  };
}
