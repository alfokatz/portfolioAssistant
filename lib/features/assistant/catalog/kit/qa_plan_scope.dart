import 'package:flutter/widgets.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';

/// Un pedido de paywall desde una card del catálogo.
class QaPaywallRequest {
  const QaPaywallRequest({
    required this.source,
    this.ticker,
    this.surfaceId,
    this.preview,
  });

  /// De dónde viene, para medir conversiones: "analysis_locked_news",
  /// "chip_analysis", "weekly_free_analysis"…
  final String source;
  final String? ticker;

  /// Surface de la card que lo pidió: después de comprar, se le traen los
  /// datos de Gold para desbloquearla en el lugar.
  final String? surfaceId;

  /// Vista previa que la hoja muestra como gancho (sin datos de Gold).
  final WidgetBuilder? preview;
}

/// El plan del usuario visto desde las cards: qué incluye, si le queda el
/// análisis de cortesía de la semana y cómo abrir el paywall.
///
/// La provee la pantalla del asistente. Sin scope (tests aislados, cards
/// fuera del chat) no hay nada bloqueado: las cards se ven como Gold y no
/// ofrecen paywall — nunca un candado que no lleva a ningún lado.
class QaPlanScope extends InheritedWidget {
  const QaPlanScope({
    super.key,
    required this.tier,
    required this.weeklyFreeAnalysisAvailable,
    required this.heldTickers,
    required this.openPaywall,
    required super.child,
  });

  final SubscriptionTier tier;

  /// `null` = todavía no se sabe (no se muestra el texto de "gratis").
  final bool? weeklyFreeAnalysisAvailable;
  final Set<String> heldTickers;
  final ValueChanged<QaPaywallRequest> openPaywall;

  static QaPlanScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<QaPlanScope>();

  bool allows(PlanFeature feature) => PlanMatrix.allows(tier, feature);

  /// Si el análisis de cortesía de la semana cubre [ticker]: Free solo en
  /// sus propios tickers (la cortesía abre Gold, no el mercado de Premium).
  bool freeAnalysisCovers(String ticker) {
    if (weeklyFreeAnalysisAvailable != true) return false;
    if (!PlanMatrix.hasWeeklyFreeAnalysis(tier)) return false;
    if (tier == SubscriptionTier.free) {
      return heldTickers.contains(ticker.toUpperCase());
    }
    return true;
  }

  @override
  bool updateShouldNotify(QaPlanScope oldWidget) =>
      oldWidget.tier != tier ||
      oldWidget.weeklyFreeAnalysisAvailable != weeklyFreeAnalysisAvailable ||
      oldWidget.heldTickers.length != heldTickers.length ||
      !oldWidget.heldTickers.containsAll(heldTickers);
}
