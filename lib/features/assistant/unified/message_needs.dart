import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/broad_market_query.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/company_name_candidate_extractor.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/company_ticker_resolver.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/news_query_detector.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/ticker_extractor.dart';

/// Qué datos necesita UN mensaje, decidido desde cero para ese mensaje —
/// nunca según qué se preguntó antes (salvo el ticker de seguimiento, ver
/// [MessageNeedsAnalyzer.analyze]). Es lo que decide qué se pide a Yahoo /
/// Finnhub y qué gating de plan aplica, ANTES de llamar al modelo.
class MessageNeeds {
  const MessageNeeds({
    required this.tickers,
    required this.heldTickers,
    required this.isConceptual,
    required this.mentionsOwnPortfolio,
    required this.needsAllPositionPeriods,
    required this.isExplicitNewsRequest,
    required this.isNewsQuery,
    this.marketProxyTicker,
    this.ambiguousCandidate,
    this.ambiguousMatches,
    this.usedFollowUpTicker = false,
  });

  /// Tickers sobre los que es la pregunta (máx. 3), en orden de aparición.
  final List<String> tickers;

  /// Subconjunto de [tickers] que el usuario tiene en cartera.
  final Set<String> heldTickers;

  /// Pregunta conceptual ("¿qué es un ETF, como SPY?"): no se pide ningún
  /// dato de ticker aunque el texto nombre uno como ejemplo.
  final bool isConceptual;

  final bool mentionsOwnPortfolio;

  /// Superlativo/período sobre las propias posiciones ("¿cuál de mis
  /// acciones subió más esta semana?") — necesita `position_periods` de
  /// TODAS las tenencias.
  final bool needsAllPositionPeriods;

  /// Pedido explícito de noticias sobre un ticker de este mensaje — ver
  /// `isExplicitNewsRequest`. Es lo que se gatea por plan y pesa más en la
  /// cuota.
  final bool isExplicitNewsRequest;

  /// El criterio amplio que usa `ExploreNewsEnricher` para decidir si trae
  /// titulares (se conserva igual para no cambiar ese comportamiento).
  final bool isNewsQuery;

  final String? marketProxyTicker;
  final String? ambiguousCandidate;
  final List<({String symbol, String description})>? ambiguousMatches;

  /// El ticker vino del turno anterior, no de este mensaje.
  final bool usedFollowUpTicker;

  /// Tickers que el usuario NO tiene (incluye el proxy de mercado): son los
  /// que requieren datos de mercado externos → plan pago.
  Set<String> get externalTickers => {
    for (final t in tickers)
      if (!heldTickers.contains(t)) t,
  };

  bool get needsMarketData => externalTickers.isNotEmpty;
}

abstract final class MessageNeedsAnalyzer {
  static final _conceptualPattern = RegExp(
    r'(?:qu[eé] es\b|qu[eé] son\b|c[oó]mo funciona|explic[aá]me|explic[aá]\b|'
    r'qu[eé] significa|significa\b|diferencia entre)',
    caseSensitive: false,
  );

  /// Intención de precio/movimiento/datos: si aparece, una frase con "qué
  /// es" deja de ser puramente conceptual.
  static const _dataIntentWords = [
    'precio',
    'cotiza',
    'a cuánto',
    'a cuanto',
    'vale ',
    'subió',
    'subio',
    'bajó',
    'cayó',
    'cayo',
    'rinde',
    'rindió',
    'le fue',
    'noticia',
    'reporta',
    'resultados',
    'comparame',
    'compará',
  ];

  static const _ownPortfolioWords = [
    'mi portfolio',
    'mi cartera',
    'mis posiciones',
    'mis acciones',
    'mis inversiones',
    'mis tenencias',
    'cómo voy',
    'como voy',
    'me fue',
    'gané',
    'perdí',
    'posiciones tengo',
    'estoy invertido',
    'tengo invertido',
  ];

  static const _superlativeWords = [
    'mejor',
    'peor',
    'subió más',
    'más subió',
    'bajó más',
    'más bajó',
    'cayó más',
    'más cayó',
  ];

  static const _periodWords = [
    'hoy',
    'semana',
    'mes',
    'trimestre',
    'año',
    'anual',
    'diario',
  ];


  /// Una pregunta sin ticker que evidentemente sigue hablando del ticker
  /// anterior: "¿y las noticias?", "¿por qué?", "¿cuándo reporta?", "¿y
  /// este año?".
  static const _followUpCueWords = [
    'noticia',
    'novedad',
    'qué pasó',
    'que pasó',
    'por qué',
    'por que',
    'reporta',
    'resultados',
    'precio',
    'cotiza',
    'a cuánto',
    'a cuanto',
  ];

  static bool _containsAny(String lower, List<String> words) =>
      words.any(lower.contains);

  static bool isConceptual(String message) {
    final lower = message.toLowerCase();
    return _conceptualPattern.hasMatch(lower) &&
        !_containsAny(lower, _dataIntentWords) &&
        !_containsAny(lower, _ownPortfolioWords);
  }

  static bool _hasFollowUpCue(String lower) {
    if (_containsAny(lower, _followUpCueWords)) return true;
    // "¿y este año?", "y en el mes?" — período suelto encadenado con "y".
    final trimmed = lower.replaceFirst(RegExp(r'^[¿\s]+'), '');
    return trimmed.startsWith('y ') && _containsAny(lower, _periodWords);
  }

  /// [followUpTicker]: ticker del último turno que resolvió uno (ver
  /// `UnifiedTurnHistory`). Solo se usa si este mensaje no nombra ningún
  /// ticker, no es conceptual ni sobre la propia cartera, y tiene una
  /// señal clara de seguimiento — un "hola" después de hablar de AAPL no
  /// vuelve a pedir datos de AAPL.
  static Future<MessageNeeds> analyze({
    required String message,
    PortfolioSummary? summary,
    String? followUpTicker,
    CompanyTickerResolver? tickerResolver,
  }) async {
    final lower = message.toLowerCase();
    final conceptual = isConceptual(message);
    final ownPortfolio = _containsAny(lower, _ownPortfolioWords);
    final superlative = _containsAny(lower, _superlativeWords);
    final heldAll = {
      for (final v in summary?.valuations ?? const []) v.position.ticker,
    };

    var tickers = <String>[];
    String? proxy;
    String? ambiguousCandidate;
    List<({String symbol, String description})>? ambiguousMatches;
    var usedFollowUp = false;

    if (!conceptual) {
      tickers = TickerExtractor.extractTickers(message);

      // B5: "¿qué acción subió más hoy en el mercado?" no tiene respuesta
      // con un proxy — no se trae SPY para un superlativo de mercado.
      if (tickers.isEmpty &&
          !ownPortfolio &&
          !superlative &&
          isBroadMarketQuery(message)) {
        tickers = [broadMarketProxyTicker];
        proxy = broadMarketProxyTicker;
      }

      if (tickers.isEmpty && !ownPortfolio && tickerResolver != null) {
        final candidate = CompanyNameCandidateExtractor.extract(message);
        if (candidate != null) {
          final resolution = await tickerResolver.resolve(candidate);
          if (resolution.ticker != null) {
            tickers = [resolution.ticker!];
          } else if (resolution.matches != null) {
            ambiguousCandidate = candidate;
            ambiguousMatches = [
              for (final m in resolution.matches!)
                (symbol: m.symbol, description: m.description),
            ];
          }
        }
      }

      if (tickers.isEmpty &&
          ambiguousCandidate == null &&
          !ownPortfolio &&
          followUpTicker != null &&
          _hasFollowUpCue(lower)) {
        tickers = [followUpTicker];
        usedFollowUp = true;
      }
    }

    return MessageNeeds(
      tickers: tickers,
      heldTickers: {
        for (final t in tickers)
          if (heldAll.contains(t)) t,
      },
      isConceptual: conceptual,
      mentionsOwnPortfolio: ownPortfolio,
      needsAllPositionPeriods:
          !conceptual &&
          ownPortfolio &&
          (superlative || _containsAny(lower, _periodWords)),
      isExplicitNewsRequest:
          !conceptual && tickers.isNotEmpty && isExplicitNewsRequest(message),
      isNewsQuery: isNewsQuery(message),
      marketProxyTicker: proxy,
      ambiguousCandidate: ambiguousCandidate,
      ambiguousMatches: ambiguousMatches,
      usedFollowUpTicker: usedFollowUp,
    );
  }
}
