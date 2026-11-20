import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_numbers.dart';

/// Interfaz mínima de quien escribe la prosa del brief con Porty (el LLM).
///
/// La implementa el dueño del chat sobre su `DailyBriefGenerator` (§3.9:
/// `generate({day, input, language}) → DailyBriefGeneration`, nunca lanza);
/// el controlador del brief solo conoce esta firma. Mientras esa clase no
/// exista, `dailyBriefWriterProvider` devuelve un escritor que falla y el
/// brief se muestra con solo los números.
abstract class DailyBriefWriter {
  Future<DailyBriefWriting> write(DailyBriefWritingRequest request);
}

/// Lo que se le da a Porty para escribir (todo ya calculado o validado).
class DailyBriefWritingRequest {
  const DailyBriefWritingRequest({
    required this.day,
    required this.language,
    required this.numbers,
    required this.held,
    required this.watch,
    required this.market,
    this.assetClasses = const {},
  });

  /// `YYYY-MM-DD` local.
  final String day;

  /// `es` o `en`.
  final String language;
  final DailyBriefNumbers numbers;
  final List<BriefHeadline> held;
  final List<BriefHeadline> watch;
  final List<BriefMarketFact> market;

  /// Clases de activo que tiene el usuario (`crypto`, `bond`, `etf`,
  /// `equity`): la frase de conexión de un tema solo vale si tiene la clase.
  final Set<String> assetClasses;
}

/// Una línea escrita por Porty que cuelga de un titular (`news_id`).
class BriefLine {
  const BriefLine({required this.ticker, required this.text, this.newsId});

  final String ticker;
  final String text;
  final String? newsId;

  Map<String, Object?> toJson() => {
    'ticker': ticker,
    'text': text,
    if (newsId != null) 'news_id': newsId,
  };

  static BriefLine? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final ticker = raw['ticker'];
    final text = raw['text'];
    if (ticker is! String || text is! String || text.trim().isEmpty) {
      return null;
    }
    return BriefLine(
      ticker: ticker,
      text: text,
      newsId: raw['news_id'] is String ? raw['news_id'] as String : null,
    );
  }
}

/// La prosa validada: `why`, `held_news`, `watch_news` y la `connection` de
/// cada hecho de mercado (por `topic_id`; `null` = sin conexión).
class DailyBriefProse {
  const DailyBriefProse({
    this.why = const [],
    this.held = const [],
    this.watch = const [],
    this.connections = const {},
  });

  static const empty = DailyBriefProse();

  final List<BriefLine> why;
  final List<BriefLine> held;
  final List<BriefLine> watch;
  final Map<String, String?> connections;

  bool get isEmpty =>
      why.isEmpty && held.isEmpty && watch.isEmpty && connections.isEmpty;
}

/// El resultado de escribir. Nunca lanza: con [error], [prose] es lo que se
/// haya podido salvar (o vacío).
class DailyBriefWriting {
  const DailyBriefWriting({
    required this.prose,
    this.rounds = 0,
    this.removedItems = 0,
    this.error,
  });

  final DailyBriefProse prose;

  /// Llamadas al LLM (0, 1 o 2).
  final int rounds;

  /// Ítems que el validador sacó.
  final int removedItems;
  final String? error;

  bool get failed => error != null && prose.isEmpty;
}
