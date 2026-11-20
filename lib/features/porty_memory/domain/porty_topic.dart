/// Un ticker del que el usuario le habló a Porty: la última vez, con qué
/// pregunta y a qué precio estaba (fila de `porty_topics`). Lo arma la app
/// con las tools de cada turno, sin el modelo.
class PortyTopic {
  const PortyTopic({
    required this.ticker,
    required this.question,
    required this.lastAskedAt,
    this.priceAt,
    this.held = false,
    this.times = 1,
  });

  final String ticker;
  final String question;
  final DateTime lastAskedAt;

  /// Precio del ticker ese día; `null` si no se trajo.
  final double? priceAt;
  final bool held;
  final int times;

  /// Cuántos días atrás entra en el brief del chat.
  static const briefWindow = Duration(days: 30);

  /// Cuántos van en el brief (los más recientes).
  static const maxInBrief = 6;

  static PortyTopic? fromRow(Map<String, dynamic> row) {
    final ticker = (row['ticker'] as String?)?.trim();
    final question = (row['question'] as String?)?.trim();
    final at = DateTime.tryParse('${row['last_asked_at']}');
    if (ticker == null || ticker.isEmpty || question == null || at == null) {
      return null;
    }
    final price = row['price_at'];
    return PortyTopic(
      ticker: ticker,
      question: question,
      lastAskedAt: at,
      priceAt: price is num ? price.toDouble() : double.tryParse('$price'),
      held: row['held'] == true,
      times: row['times'] is int ? row['times'] as int : 1,
    );
  }

  /// Para PORTFOLIO_BRIEF (`recent_topics`): de qué habló, cuándo y a qué
  /// precio. El precio de hoy lo trae `get_quote`, nunca el modelo.
  Map<String, Object?> toBrief(DateTime now) => {
    'ticker': ticker,
    'asked': _date(lastAskedAt.toLocal()),
    'days_ago': now.difference(lastAskedAt).inDays,
    if (priceAt != null) 'price_then': priceAt,
    if (held) 'held': true,
    if (times > 1) 'times': times,
  };

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Lo que se registra de un turno (ver `PortyTopicsExtractor`).
class PortyTopicDraft {
  const PortyTopicDraft({
    required this.ticker,
    required this.question,
    this.priceAt,
    this.held = false,
  });

  final String ticker;
  final String question;
  final double? priceAt;
  final bool held;

  Map<String, Object?> toJson() => {
    'ticker': ticker,
    'question': question,
    if (priceAt != null) 'price_at': priceAt,
    'held': held,
  };
}
