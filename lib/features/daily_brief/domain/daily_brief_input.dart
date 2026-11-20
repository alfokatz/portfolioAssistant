import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_numbers.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_writer.dart';

/// Todo lo que entra al LLM para escribir el brief del día (§3.9), ya
/// calculado o validado. Porty solo agrega prosa que referencia estos datos
/// por id: los números, el medio y el link los pone la app.
///
/// Desvío de la spec: reusa los tipos del bundle (`BriefHeadline`,
/// `BriefMarketFact`) en vez de `BriefNewsItem`/`BriefMarketItem` nuevos, y
/// no lleva `signals` (la app los escribe sin IA; al modelo no le hacen
/// falta).
class DailyBriefInput {
  const DailyBriefInput({
    required this.language,
    required this.numbers,
    this.held = const [],
    this.watch = const [],
    this.market = const [],
    this.assetClasses = const {},
  });

  /// El que pide el controlador: `DailyBriefWritingRequest` ya trae todo.
  factory DailyBriefInput.fromRequest(DailyBriefWritingRequest r) =>
      DailyBriefInput(
        language: r.language == 'en' ? 'en' : 'es',
        numbers: r.numbers,
        held: r.held,
        watch: r.watch,
        market: r.market,
        assetClasses: r.assetClasses,
      );

  /// `es` o `en`: el idioma del brief y del prompt.
  final String language;
  final DailyBriefNumbers numbers;

  /// Titulares de posiciones de la cartera.
  final List<BriefHeadline> held;

  /// Titulares de la watchlist (solo Gold; el servidor ya los filtró).
  final List<BriefHeadline> watch;

  /// Hechos de mercado en el orden del servidor (los primeros [maxMarket]
  /// son los que muestra el brief).
  final List<BriefMarketFact> market;

  /// Clases de activo que tiene el usuario (`crypto`, `bond`, `etf`,
  /// `equity`).
  final Set<String> assetClasses;

  /// "Por qué" como mucho (las posiciones que más movieron).
  static const maxWhy = 3;

  /// Líneas de noticias de cartera y de watchlist como mucho.
  static const maxHeld = 3;
  static const maxWatch = 3;

  /// Hechos de mercado del brief con cruce como mucho.
  static const maxMarket = 3;

  /// Movimiento de una posición, en palabras: el modelo nunca ve cifras.
  static const flatBelowPct = 0.05;
  static const smallBelowPct = 1.0;
  static const moderateBelowPct = 3.0;

  /// Peso de una posición en la cartera, en palabras.
  static const mediumWeightPct = 5.0;
  static const largeWeightPct = 20.0;

  /// Las posiciones que más movieron y tienen un titular propio de cartera:
  /// a esas Porty les escribe un "por qué".
  List<BriefMover> get whyMovers {
    final withNews = {for (final h in held) h.ticker.toUpperCase()};
    return [
      for (final m in numbers.movers)
        if (withNews.contains(m.ticker.toUpperCase())) m,
    ].take(maxWhy).toList();
  }

  /// Hechos de mercado a los que Porty puede escribirles una `connection`:
  /// con tema, con la frase fija del tema y solo si el usuario tiene la
  /// clase de activo (si no, la conexión va `null` y ni se le muestra).
  List<BriefMarketFact> get connectable => [
    for (final f in market.take(maxMarket))
      if (f.topicId != null &&
          (f.assetLink?.trim().isNotEmpty ?? false) &&
          f.assetClass != null &&
          assetClasses.contains(f.assetClass))
        f,
  ];

  /// Sin titulares ni cruces posibles no hay nada que escribir: no se llama
  /// al LLM.
  bool get hasWork =>
      held.isNotEmpty || watch.isNotEmpty || connectable.isNotEmpty;

  static String direction(double pct) =>
      pct.abs() < flatBelowPct ? 'flat' : (pct > 0 ? 'up' : 'down');

  static String size(double pct) {
    final a = pct.abs();
    if (a < smallBelowPct) return 'small';
    return a < moderateBelowPct ? 'moderate' : 'large';
  }

  static String weight(double pct) {
    if (pct >= largeWeightPct) return 'large';
    return pct >= mediumWeightPct ? 'medium' : 'small';
  }

  /// El JSON del mensaje de usuario. Sin cifras: dirección, tamaño y peso
  /// en palabras (igual que el informe semanal).
  Map<String, Object?> toPromptJson() {
    final why = {for (final m in whyMovers) m.ticker};
    return {
      'language': language,
      'movers': [
        for (final m in numbers.movers)
          {
            'ticker': m.ticker,
            'direction': direction(m.pct),
            'size': size(m.pct),
            'weight': weight(m.weightPct),
            'needs_why': why.contains(m.ticker),
          },
      ],
      'held_news': [for (final h in held) h.toPromptJson()],
      'watch_news': [for (final h in watch) h.toPromptJson()],
      'market': [
        for (final f in connectable)
          {'topic_id': f.topicId, 'fact': f.text, 'asset_link': f.assetLink},
      ],
    };
  }
}
