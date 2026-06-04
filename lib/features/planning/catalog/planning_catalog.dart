import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:portfolio_assistant/features/planning/catalog/planning_catalog_widgets.dart';
import 'package:portfolio_assistant/features/genui_core/prompts/critical_output_rules.dart';
import 'package:portfolio_assistant/features/genui_core/widgets/guarded_catalog_widget.dart';

const _milestoneStatusEnum = ['completed', 'current', 'upcoming'];
const _impactEnum = ['high', 'medium', 'low'];
const _effortEnum = ['easy', 'moderate', 'hard'];

final _scenarioItemSchema = S.object(
  properties: {
    'label': S.string(),
    'color': S.string(),
    'projectedValue': S.number(),
    'monthlyRequired': S.number(),
  },
  required: ['label', 'color', 'projectedValue', 'monthlyRequired'],
);

final _milestoneItemSchema = S.object(
  properties: {
    'date': S.string(),
    'label': S.string(),
    'targetValue': S.number(),
    'status': S.string(enumValues: _milestoneStatusEnum),
  },
  required: ['date', 'label', 'targetValue', 'status'],
);

final CatalogItem goalCardItem = CatalogItem(
  name: 'GoalCard',
  dataSchema: S.object(
    description: 'Resumen visual de la meta financiera del usuario.',
    properties: {
      'goalLabel': S.string(),
      'targetAmount': S.number(),
      'targetDate': S.string(),
      'currentProgress': S.number(minimum: 0, maximum: 100),
      'currentSaved': S.number(),
      'monthsRemaining': S.number(),
    },
    required: [
      'goalLabel',
      'targetAmount',
      'targetDate',
      'currentProgress',
      'currentSaved',
      'monthsRemaining',
    ],
  ),
  widgetBuilder: (ctx) => guardedCatalogWidget(ctx, PlanningCatalogWidgets.goalCard),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "GoalCard",
    "goalLabel": "Retiro",
    "targetAmount": 500000,
    "targetDate": "2045-01-01",
    "currentProgress": 12,
    "currentSaved": 24350.80,
    "monthsRemaining": 228
  }
]
''',
  ],
);

final CatalogItem projectionChartItem = CatalogItem(
  name: 'ProjectionChart',
  dataSchema: S.object(
    description: 'Gráfico de proyección con tres escenarios.',
    properties: {
      'currentValue': S.number(),
      'targetValue': S.number(),
      'targetDate': S.string(),
      'scenarios': S.list(items: _scenarioItemSchema, minItems: 3, maxItems: 3),
      'highlightScenario': S.string(),
    },
    required: [
      'currentValue',
      'targetValue',
      'targetDate',
      'scenarios',
      'highlightScenario',
    ],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PlanningCatalogWidgets.projectionChart),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "ProjectionChart",
    "currentValue": 60000,
    "targetValue": 500000,
    "targetDate": "2046-05-28",
    "highlightScenario": "Moderado",
    "scenarios": [
      {
        "label": "Conservador",
        "color": "#8B95A8",
        "projectedValue": 420000,
        "monthlyRequired": 850
      },
      {
        "label": "Moderado",
        "color": "#2979FF",
        "projectedValue": 500000,
        "monthlyRequired": 620
      },
      {
        "label": "Optimista",
        "color": "#00C853",
        "projectedValue": 580000,
        "monthlyRequired": 480
      }
    ]
  }
]
''',
  ],
);

final CatalogItem milestoneTimelineItem = CatalogItem(
  name: 'MilestoneTimeline',
  dataSchema: S.object(
    description: 'Línea de tiempo con hitos de la meta.',
    properties: {
      'milestones': S.list(items: _milestoneItemSchema),
    },
    required: ['milestones'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PlanningCatalogWidgets.milestoneTimeline),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "MilestoneTimeline",
    "milestones": [
      {
        "date": "2026-05-28",
        "label": "25% de la meta",
        "targetValue": 125000,
        "status": "completed"
      },
      {
        "date": "2031-05-28",
        "label": "50% de la meta",
        "targetValue": 250000,
        "status": "current"
      },
      {
        "date": "2036-05-28",
        "label": "75% de la meta",
        "targetValue": 375000,
        "status": "upcoming"
      },
      {
        "date": "2046-05-28",
        "label": "Meta alcanzada",
        "targetValue": 500000,
        "status": "upcoming"
      }
    ]
  }
]
''',
  ],
);

final CatalogItem actionPriorityCardItem = CatalogItem(
  name: 'ActionPriorityCard',
  dataSchema: S.object(
    description: 'Acción concreta priorizada para alcanzar la meta.',
    properties: {
      'priority': S.number(minimum: 1, maximum: 3),
      'title': S.string(),
      'description': S.string(),
      'impact': S.string(enumValues: _impactEnum),
      'effort': S.string(enumValues: _effortEnum),
      'actionEvent': S.string(),
    },
    required: ['priority', 'title', 'description', 'impact', 'effort'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PlanningCatalogWidgets.actionPriorityCard),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "ActionPriorityCard",
    "priority": 1,
    "title": "Aumentá tu aporte mensual",
    "description": "Sumar \$200 por mes te acerca mucho más rápido a tu meta de retiro.",
    "impact": "high",
    "effort": "easy",
    "actionEvent": "flow_invest_open"
  }
]
''',
  ],
);

final CatalogItem gapAnalysisCardItem = CatalogItem(
  name: 'GapAnalysisCard',
  dataSchema: S.object(
    description: 'Comparación entre el ritmo actual y el necesario.',
    properties: {
      'currentMonthlyContribution': S.number(),
      'requiredMonthlyContribution': S.number(),
      'gap': S.number(),
      'yearsToGoalAtCurrentRate': S.number(),
      'yearsToGoalIfGapClosed': S.number(),
      'message': S.string(),
    },
    required: [
      'currentMonthlyContribution',
      'requiredMonthlyContribution',
      'gap',
      'yearsToGoalAtCurrentRate',
      'yearsToGoalIfGapClosed',
      'message',
    ],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PlanningCatalogWidgets.gapAnalysisCard),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "GapAnalysisCard",
    "currentMonthlyContribution": 500,
    "requiredMonthlyContribution": 980,
    "gap": 480,
    "yearsToGoalAtCurrentRate": 34,
    "yearsToGoalIfGapClosed": 19,
    "message": "Con tu aporte actual llegás en 34 años. Aumentando \$480 por mes lo lográs en 19."
  }
]
''',
  ],
);

const String _planningRules = '''
LONG-TERM PLANNING RULES:

1. ALWAYS start with GoalCard to confirm understanding of the goal.
   If amount or date is missing, infer sensible defaults from the user message
   and ask for missing details inside widget text (GoalCard label, GapAnalysisCard
   message, or ActionPriorityCard description). NEVER respond with plain text.

2. ALWAYS show ProjectionChart with all 3 scenarios:
   - Conservador: 6% annual return
   - Moderado: use /portfolio/monthly_return_avg if available, else 10%
   - Optimista: 15% annual return
   Default highlightScenario: "Moderado"

3. Include GapAnalysisCard when current contribution is insufficient
   to reach the goal at the recommended scenario.

4. ActionPriorityCards: maximum 3, ordered by impact descending.
   At least one must have actionEvent: "flow_invest_open".

5. MilestoneTimeline required for goals longer than 3 years.
   Create milestones every 25% of progress.

6. NEVER use financial jargon:
   - "rendimiento anualizado" → "cuánto crece por año"
   - "diversificación" → "no poner todo en un solo lugar"
   - "volatilidad" → "cuánto pueden subir o bajar"

7. For "what if" scenarios, recalculate ProjectionChart and
   GapAnalysisCard with the new parameters.

8. NEVER respond with plain text. Every response must compose
   at least GoalCard + ProjectionChart.

9. CRITICAL — SURFACE ID: ALWAYS use surfaceId "long_term_planning" in both
   createSurface and updateComponents messages.

10. CRITICAL — A2UI OUTPUT: Always output exactly TWO newline-separated JSON objects:
   First: {"version":"v0.9","createSurface":{"surfaceId":"long_term_planning","catalogId":"https://a2ui.org/specification/v0_9/standard_catalog.json"}}
   Second: {"version":"v0.9","updateComponents":{"surfaceId":"long_term_planning","components":[...]}}
   The components array MUST include a component with "id":"root". When showing
   multiple widgets, use a Column as root with child component IDs.

11. CRITICAL FOR GPT-4o: Always respond with valid JSON strictly
   following the catalog schemas. Do not add extra fields, do not
   omit required fields. Respond ONLY with raw JSON. No explanations,
   no markdown, no code blocks. Raw JSON only.
   If you are unsure about a value, use a sensible default rather
   than omitting the field or breaking the JSON structure.

Data paths (read-only unless noted):
- /portfolio/total_value → current portfolio value
- /portfolio/monthly_return_avg → average monthly return
- /user/monthly_contribution → current monthly contribution
- /goals/target_amount → goal amount (writable)
- /goals/target_date → goal date ISO (writable)
- /goals/label → goal name (writable)

Use catalogId "https://a2ui.org/specification/v0_9/standard_catalog.json" in createSurface messages.
Compose surfaces using a Column as root with child component IDs when showing multiple widgets.
All user-facing text must be in simple Spanish.
''';

/// Catálogo del flujo de planificación a largo plazo.
///
/// Los items base (Column, Text, etc.) vienen de [BasicCatalogItems] del SDK.
abstract final class PlanningCatalog {
  static Catalog build() {
    final base = BasicCatalogItems.asCatalog();
    return base.copyWith(
      newItems: [
        goalCardItem,
        projectionChartItem,
        milestoneTimelineItem,
        actionPriorityCardItem,
        gapAnalysisCardItem,
      ],
      systemPromptFragments: [
        criticalOutputFormatRules,
        ...base.systemPromptFragments,
        _planningRules,
      ],
    );
  }
}
