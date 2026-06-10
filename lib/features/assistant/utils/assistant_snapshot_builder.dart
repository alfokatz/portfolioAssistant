import 'dart:convert';

import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_context_builder.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_news_enricher.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/invest_context_builder.dart';
import 'package:portfolio_assistant/features/assistant/modes/plan/plan_context_builder.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/utils/portfolio_context_builder.dart';
import 'package:portfolio_assistant/features/assistant/utils/position_periods_builder.dart';

/// Construye el JSON de snapshot enviado al asistente según el modo activo.
Future<String> buildSnapshotJson({
  required AssistantMode mode,
  PortfolioSummary? summary,
  List<PortfolioHistoryPoint> history = const [],
  List<ClosedPosition> closedPositions = const [],
  QuoteRepository? quoteRepository,
  DateTime? asOf,
  String userMessage = '',
  double? riskProfile,
  ({String label, double targetAmount, String targetDate})? savedGoal,
  double? monthlyContribution,
  ExploreNewsEnricher? exploreNewsEnricher,
}) async {
  final timestamp = (asOf ?? DateTime.now()).toUtc().toIso8601String();

  switch (mode) {
    case AssistantMode.portfolio:
      final hasOpen = summary != null && summary.valuations.isNotEmpty;
      final positionPeriods =
          hasOpen && quoteRepository != null
              ? await PositionPeriodsBuilder.build(
                summary: summary,
                quoteRepository: quoteRepository,
              )
              : const <String, Map<String, Object?>>{};
      return PortfolioContextBuilder.buildJson(
        summary,
        history: history,
        positionPeriods: positionPeriods,
        closedPositions: closedPositions,
        asOf: asOf,
      );
    case AssistantMode.learn:
      return jsonEncode({'mode': 'learn', 'as_of': timestamp});
    case AssistantMode.explore:
      if (quoteRepository == null) {
        return jsonEncode({
          'mode': 'explore',
          'data_source': 'yahoo_finance',
          'explore_tickers': <String, dynamic>{},
          'as_of': timestamp,
        });
      }
      final exploreSnapshot = await ExploreContextBuilder.build(
        userMessage: userMessage,
        quoteRepository: quoteRepository,
        summary: summary,
        asOf: asOf,
        newsEnricher: exploreNewsEnricher ?? ExploreNewsEnricher(),
      );
      return jsonEncode(exploreSnapshot);
    case AssistantMode.invest:
      if (quoteRepository == null) {
        return jsonEncode({
          'mode': 'invest',
          'data_source': 'yahoo_finance',
          'as_of': timestamp,
          'has_budget': false,
          'candidates': <Map<String, Object?>>[],
        });
      }
      final investSnapshot = await InvestContextBuilder.build(
        userMessage: userMessage,
        quoteRepository: quoteRepository,
        summary: summary,
        riskProfile: riskProfile,
        asOf: asOf,
      );
      return jsonEncode(investSnapshot);
    case AssistantMode.plan:
      final planSnapshot = await PlanContextBuilder.build(
        userMessage: userMessage,
        summary: summary,
        savedGoal: savedGoal,
        monthlyContribution: monthlyContribution,
        asOf: asOf,
      );
      return jsonEncode(planSnapshot);
  }
}
