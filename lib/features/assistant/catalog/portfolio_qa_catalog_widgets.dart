import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/reveal_step.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/typewriter_text.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/shared/utils/genui_helpers.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/advice_widgets.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/company_widgets.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/market_widgets.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/portfolio_widgets.dart';

/// Punto de entrada único que usan los `CatalogItem`. La implementación vive
/// por dominio en `widgets/market_widgets.dart`, `portfolio_widgets.dart` y
/// `advice_widgets.dart`.
abstract final class PortfolioQaCatalogWidgets {
  static Widget qaAnswerText(CatalogItemContext ctx) {
    final data = _AnswerTextData.fromMap(ctx.data as JsonMap);
    const style = TextStyle(
      color: PortfolioColors.textPrimary,
      fontSize: 15,
      height: 1.45,
    );

    // El texto de Porty es siempre el primer paso del reveal de la surface
    // (slot 0, reclamado automáticamente al montar) — recién cuando termina
    // de tipearse se habilita la próxima card. Fuera de una surface (sin
    // SurfaceRevealScope ancestro) se muestra directo, sin typewriter.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Builder(
        builder: (context) {
          final revealController = SurfaceRevealScope.maybeOf(context);
          if (revealController == null) {
            return Text(data.text, style: style);
          }
          return RevealStep(
            controller: revealController,
            builder:
                (context, active, onFinished) => TypewriterText(
                  text: data.text,
                  style: style,
                  play: active,
                  onComplete: onFinished,
                  onWordRevealed:
                      PortyHapticsService.maybeOf(context)?.streamTick,
                ),
          );
        },
      ),
    );
  }

  static Widget qaTickerSnapshot(CatalogItemContext ctx) =>
      MarketWidgets.qaTickerSnapshot(ctx);

  static Widget qaTickerMove(CatalogItemContext ctx) =>
      MarketWidgets.qaTickerMove(ctx);

  static Widget qaPriceChart(CatalogItemContext ctx) =>
      MarketWidgets.qaPriceChart(ctx);

  static Widget qaCompareChart(CatalogItemContext ctx) =>
      MarketWidgets.qaCompareChart(ctx);

  static Widget qaEarningsCalendar(CatalogItemContext ctx) =>
      CompanyWidgets.qaEarningsCalendar(ctx);

  static Widget qaNewsSummary(CatalogItemContext ctx) =>
      CompanyWidgets.qaNewsSummary(ctx);

  static Widget qaFundamentals(CatalogItemContext ctx) =>
      CompanyWidgets.qaFundamentals(ctx);

  static Widget qaMetricStrip(CatalogItemContext ctx) =>
      MarketWidgets.qaMetricStrip(ctx);

  static Widget qaComparisonRow(CatalogItemContext ctx) =>
      MarketWidgets.qaComparisonRow(ctx);

  static Widget qaPositionsSnapshot(CatalogItemContext ctx) =>
      PortfolioWidgets.qaPositionsSnapshot(ctx);

  static Widget qaPeriodChange(CatalogItemContext ctx) =>
      PortfolioWidgets.qaPeriodChange(ctx);

  static Widget qaConcentrationBar(CatalogItemContext ctx) =>
      PortfolioWidgets.qaConcentrationBar(ctx);

  static Widget qaPnLBreakdown(CatalogItemContext ctx) =>
      PortfolioWidgets.qaPnLBreakdown(ctx);

  static Widget qaTopMovers(CatalogItemContext ctx) =>
      PortfolioWidgets.qaTopMovers(ctx);

  static Widget qaPositionList(CatalogItemContext ctx) =>
      PortfolioWidgets.qaPositionList(ctx);

  static Widget qaClosedPositionList(CatalogItemContext ctx) =>
      PortfolioWidgets.qaClosedPositionList(ctx);

  static Widget qaTipBanner(CatalogItemContext ctx) =>
      AdviceWidgets.qaTipBanner(ctx);

  static Widget qaInvestOption(CatalogItemContext ctx) =>
      AdviceWidgets.qaInvestOption(ctx);

  static Widget qaBudgetSplit(CatalogItemContext ctx) =>
      AdviceWidgets.qaBudgetSplit(ctx);

  static Widget qaInvestConfirm(CatalogItemContext ctx) =>
      AdviceWidgets.qaInvestConfirm(ctx);

  static Widget qaGoalCard(CatalogItemContext ctx) =>
      AdviceWidgets.qaGoalCard(ctx);

  static Widget qaProjectionStrip(CatalogItemContext ctx) =>
      AdviceWidgets.qaProjectionStrip(ctx);

  static Widget qaProjectionChart(CatalogItemContext ctx) =>
      AdviceWidgets.qaProjectionChart(ctx);

  static Widget qaMilestoneList(CatalogItemContext ctx) =>
      AdviceWidgets.qaMilestoneList(ctx);
}

final class _AnswerTextData {
  _AnswerTextData({required this.text});

  factory _AnswerTextData.fromMap(JsonMap map) {
    return _AnswerTextData(
      text: GenUiHelpers.safeString(map['text'], defaultValue: ''),
    );
  }

  final String text;
}
