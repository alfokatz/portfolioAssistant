/// Las áreas de Porty: cada tool y cada widget del chat pertenece a una.
/// Es el mapa para crecer sin que el prompt crezca (ver
/// docs/superpowers/research/2026-10-24-porty-escalable.md):
///
/// - cada área tiene un presupuesto de tokens fijos (sus tools y los
///   widgets que van siempre en el prompt), controlado por
///   `test/features/assistant/areas/porty_areas_test.dart`;
/// - lo que un área solo necesita DESPUÉS de traer sus datos (reglas de
///   respuesta y esquemas de sus widgets) se declara en [PortyAreaSpec.deferred]:
///   con el prompt "lean" no viaja en el prefijo fijo sino con el resultado
///   de la tool (`area_spec`, ver `AreaSpecs`), y solo cuando se usa.
///
/// El "router" es la elección de tools que el modelo ya hace en la primera
/// ronda: no hay una llamada extra para clasificar la pregunta.
enum PortyArea {
  /// Charla, formato y lo que no es de ningún área (texto, avisos).
  conversation,

  /// La cartera propia: posiciones, períodos, cerradas.
  portfolio,

  /// Precio y evolución de cualquier ticker; búsqueda de símbolos.
  market,

  /// Fundamentals, resultados, noticias, ETFs, dividendos, análisis.
  research,

  /// Ideas y simulaciones de inversión.
  invest,

  /// Metas de ahorro, jubilación y plan de compras.
  goals,

  /// Plan de cartera y lista de seguimiento.
  planning,

  /// Registrar operaciones, ajustes y cuentas conectadas.
  actions,

  /// Alertas de precio.
  alerts,

  /// Lo que Porty recuerda del usuario.
  memory,

  /// El informe semanal.
  report,

  /// Búsqueda en la web.
  web,
}

/// Lo que viaja con el resultado de [tool] en el prompt lean: las secciones
/// de reglas (por su encabezado exacto en `assistantPromptRules`) y los
/// widgets cuyo esquema solo hace falta con esos datos.
class DeferredSpec {
  const DeferredSpec({
    required this.tool,
    this.ruleSections = const [],
    this.widgets = const [],
  });

  final String tool;
  final List<String> ruleSections;
  final List<String> widgets;
}

class PortyAreaSpec {
  const PortyAreaSpec({
    required this.area,
    required this.tools,
    required this.widgets,
    required this.budgetTokens,
    this.deferred = const [],
  });

  final PortyArea area;

  /// Las tools del área (por nombre).
  final Set<String> tools;

  /// Los widgets del área, también los diferidos.
  final Set<String> widgets;

  /// Tokens fijos que el área puede ocupar en el prompt lean: definiciones
  /// de sus tools + esquemas de sus widgets no diferidos. Medido el
  /// 2026-10-24 (o200k estimado) con ~5 % de margen: lo nuevo entra en el
  /// presupuesto de su área o viaja con el resultado de su tool.
  final int budgetTokens;

  /// Qué carga cada tool del área recién al usarse (prompt lean).
  final List<DeferredSpec> deferred;

  Set<String> get deferredWidgets => {for (final d in deferred) ...d.widgets};
}

abstract final class PortyAreas {
  static const all = <PortyAreaSpec>[
    PortyAreaSpec(
      area: PortyArea.conversation,
      tools: {},
      widgets: {
        'Column',
        'Text',
        'QaAnswerText',
        'QaTipBanner',
        'QaInfoList',
        'QaGoldTeaser',
      },
      budgetTokens: 850,
    ),
    PortyAreaSpec(
      area: PortyArea.portfolio,
      tools: {'get_portfolio_details'},
      widgets: {
        'QaPositionsSnapshot',
        'QaPeriodChange',
        'QaConcentrationBar',
        'QaPnLBreakdown',
        'QaTopMovers',
        'QaClosedPositionList',
        'QaPositionList',
        'QaComparisonRow',
      },
      budgetTokens: 1650,
    ),
    PortyAreaSpec(
      area: PortyArea.market,
      tools: {'get_quote', 'search_symbol'},
      widgets: {
        'QaPriceChart',
        'QaCompareChart',
        'QaTickerSnapshot',
        'QaTickerMove',
        'QaMetricStrip',
      },
      budgetTokens: 1400,
    ),
    PortyAreaSpec(
      area: PortyArea.research,
      tools: {
        'get_fundamentals',
        'get_earnings',
        'get_news',
        'get_etf_holdings',
        'get_dividends',
      },
      widgets: {
        'QaEarningsCalendar',
        'QaFundamentals',
        'QaCompanyAnalysis',
        'QaEtfHoldings',
        'QaNewsSummary',
      },
      budgetTokens: 1060,
      deferred: [
        DeferredSpec(
          tool: 'get_earnings',
          ruleSections: ['EARNINGS ([W:EARNINGS]) — get_earnings'],
          widgets: ['QaEarningsCalendar'],
        ),
        // El análisis de empresa siempre pide fundamentals: su card viaja
        // con ellos.
        DeferredSpec(
          tool: 'get_fundamentals',
          ruleSections: ['FUNDAMENTALS ([W:FUNDAMENTALS]) — get_fundamentals'],
          widgets: ['QaFundamentals', 'QaCompanyAnalysis'],
        ),
        DeferredSpec(
          tool: 'get_etf_holdings',
          ruleSections: ['ETF HOLDINGS ([W:ETF_HOLDINGS]) — get_etf_holdings'],
          widgets: ['QaEtfHoldings'],
        ),
        DeferredSpec(
          tool: 'get_news',
          ruleSections: ['NEWS ([W:NEWS]) — get_news'],
          widgets: ['QaNewsSummary'],
        ),
      ],
    ),
    PortyAreaSpec(
      area: PortyArea.invest,
      tools: {'get_invest_candidates'},
      // QaInvestConfirm se queda en el prompt: el usuario confirma en un
      // turno posterior, sin volver a llamar a la tool.
      widgets: {'QaInvestOption', 'QaBudgetSplit', 'QaInvestConfirm'},
      budgetTokens: 820,
      deferred: [
        DeferredSpec(
          tool: 'get_invest_candidates',
          widgets: ['QaInvestOption', 'QaBudgetSplit'],
        ),
      ],
    ),
    PortyAreaSpec(
      area: PortyArea.goals,
      tools: {
        'get_goal_projection',
        'save_goal',
        'get_monthly_buy_plan',
        'propose_goal_change',
      },
      // QaGoalStatus se queda: sale del brief, sin tool.
      widgets: {'QaSavingsPlan', 'QaBuyPlan', 'QaGoalStatus'},
      budgetTokens: 1700,
      deferred: [
        DeferredSpec(tool: 'get_goal_projection', widgets: ['QaSavingsPlan']),
        DeferredSpec(tool: 'get_monthly_buy_plan', widgets: ['QaBuyPlan']),
      ],
    ),
    PortyAreaSpec(
      area: PortyArea.planning,
      tools: {
        'get_allocation_plan',
        'propose_allocation_plan',
        'get_watchlist',
        'propose_watch',
      },
      widgets: {'QaAllocationPlan', 'QaWatchlist'},
      budgetTokens: 700,
    ),
    PortyAreaSpec(
      area: PortyArea.actions,
      tools: {
        'propose_buy',
        'propose_sell',
        'propose_delete_position',
        'get_app_settings',
        'propose_settings_change',
        'propose_broker_action',
      },
      widgets: {'QaActionProposal'},
      budgetTokens: 1400,
    ),
    PortyAreaSpec(
      area: PortyArea.alerts,
      tools: {
        'propose_price_alert',
        'list_price_alerts',
        'propose_alert_change',
      },
      widgets: {},
      budgetTokens: 470,
    ),
    PortyAreaSpec(
      area: PortyArea.memory,
      tools: {'remember_about_user', 'forget_about_user'},
      widgets: {},
      budgetTokens: 540,
    ),
    PortyAreaSpec(
      area: PortyArea.report,
      tools: {'get_weekly_report'},
      widgets: {'QaWeeklyReport'},
      budgetTokens: 150,
    ),
    PortyAreaSpec(
      area: PortyArea.web,
      tools: {'search_web'},
      widgets: {},
      budgetTokens: 280,
    ),
  ];

  static PortyAreaSpec? ofTool(String tool) {
    for (final spec in all) {
      if (spec.tools.contains(tool)) return spec;
    }
    return null;
  }

  static DeferredSpec? deferredFor(String tool) {
    for (final spec in all) {
      for (final d in spec.deferred) {
        if (d.tool == tool) return d;
      }
    }
    return null;
  }

  /// Todos los widgets que el prompt lean saca del esquema fijo.
  static Set<String> get deferredWidgets => {
    for (final spec in all) ...spec.deferredWidgets,
  };

  /// Todas las secciones de reglas que el prompt lean saca del prefijo.
  static List<String> get deferredRuleSections => [
    for (final spec in all)
      for (final d in spec.deferred) ...d.ruleSections,
  ];
}
