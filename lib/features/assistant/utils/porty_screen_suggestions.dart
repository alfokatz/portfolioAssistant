import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';

/// Una pregunta sugerida para una pantalla: la clave de traducción, sus
/// argumentos (`ticker`, `goal`) y el ícono de su tipo.
typedef PortyScreenSuggestion =
    ({String key, Map<String, String> args, IconData icon});

/// Las preguntas que ofrece la hoja de Porty según lo que el usuario está
/// mirando. Las arma la app, no el modelo (no cuestan una consulta), y
/// ninguna lleva a un paywall: lo que el plan no incluye no se sugiere.
abstract final class PortyScreenSuggestions {
  /// Cuántas se muestran como máximo (la hoja tiene que entrar en un SE).
  static const max = 3;

  static List<PortyScreenSuggestion> forScreen(
    PortyScreenContext screen,
    SubscriptionTier tier,
  ) {
    bool allows(PlanFeature f) => PlanMatrix.allows(tier, f);
    final ticker = screen.ticker?.toUpperCase();
    final goal = screen.goalLabel;
    final t = {if (ticker != null) 'ticker': ticker};
    final g = {if (goal != null) 'goal': goal};

    final all = <PortyScreenSuggestion>[
      ...switch (screen.screen) {
        PortyScreen.positionDetail when ticker != null => [
          // El "por qué" sale de las noticias (Gold); sin ellas, cómo viene.
          allows(PlanFeature.news)
              ? (
                key: 'porty_ask_position_why_moved',
                args: t,
                icon: Icons.show_chart_rounded,
              )
              : (
                key: 'porty_ask_position_week',
                args: t,
                icon: Icons.show_chart_rounded,
              ),
          (
            key: 'porty_ask_position_weight',
            args: t,
            icon: Icons.pie_chart_outline_rounded,
          ),
          allows(PlanFeature.companyAnalysis)
              ? (
                key: 'porty_ask_position_analysis',
                args: t,
                icon: Icons.article_outlined,
              )
              : (
                key: 'porty_ask_position_since_buy',
                args: t,
                icon: Icons.history_rounded,
              ),
        ],
        PortyScreen.closedPosition when ticker != null => [
          (
            key: 'porty_ask_closed_result',
            args: t,
            icon: Icons.receipt_long_outlined,
          ),
          if (allows(PlanFeature.marketData))
            (
              key: 'porty_ask_closed_since',
              args: t,
              icon: Icons.show_chart_rounded,
            ),
          (
            key: 'porty_ask_closed_lesson',
            args: t,
            icon: Icons.lightbulb_outline_rounded,
          ),
        ],
        PortyScreen.goalDetail when goal != null => [
          (key: 'porty_ask_goal_on_track', args: g, icon: Icons.flag_outlined),
          (
            key: 'porty_ask_goal_monthly',
            args: g,
            icon: Icons.savings_outlined,
          ),
          (
            key: 'porty_ask_goal_faster',
            args: g,
            icon: Icons.rocket_launch_outlined,
          ),
        ],
        PortyScreen.goals => [
          (
            key: 'porty_ask_goals_status',
            args: const {},
            icon: Icons.flag_outlined,
          ),
          (
            key: 'porty_ask_goals_priority',
            args: const {},
            icon: Icons.low_priority_rounded,
          ),
          (key: 'porty_ask_goals_new', args: const {}, icon: Icons.add_rounded),
        ],
        PortyScreen.watchlist => [
          (
            key: 'porty_ask_watchlist_movers',
            args: const {},
            icon: Icons.show_chart_rounded,
          ),
          (
            key: 'porty_ask_watchlist_vs_portfolio',
            args: const {},
            icon: Icons.compare_arrows_rounded,
          ),
          if (ticker != null && allows(PlanFeature.news))
            (
              key: 'porty_ask_watchlist_ticker',
              args: t,
              icon: Icons.visibility_outlined,
            ),
        ],
        PortyScreen.allocation => [
          (
            key: 'porty_ask_allocation_drift',
            args: const {},
            icon: Icons.donut_large_rounded,
          ),
          (
            key: 'porty_ask_allocation_contribution',
            args: const {},
            icon: Icons.calculate_outlined,
          ),
          (
            key: 'porty_ask_allocation_fits_profile',
            args: const {},
            icon: Icons.person_outline_rounded,
          ),
        ],
        PortyScreen.weeklyReport => [
          (
            key: 'porty_ask_report_summary',
            args: const {},
            icon: Icons.short_text_rounded,
          ),
          (
            key: 'porty_ask_report_watch_next',
            args: const {},
            icon: Icons.event_outlined,
          ),
          (
            key: 'porty_ask_report_best_worst',
            args: const {},
            icon: Icons.trending_up_rounded,
          ),
        ],
        // Una pantalla de algo puntual sin ese algo (no debería pasar):
        // las de la cartera, que sirven en cualquier lado.
        _ => [
          (
            key: 'portfolio_qa_chip_today',
            args: const {},
            icon: Icons.pie_chart_outline_rounded,
          ),
          (
            key: 'assistant_chip_diversified',
            args: const {},
            icon: Icons.donut_large_rounded,
          ),
        ],
      },
    ];
    return all.take(max).toList();
  }
}
