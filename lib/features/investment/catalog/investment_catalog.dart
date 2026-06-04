import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:portfolio_assistant/features/analysis/catalog/analysis_catalog.dart';
import 'package:portfolio_assistant/features/investment/catalog/investment_catalog_widgets.dart';
import 'package:portfolio_assistant/features/genui_core/prompts/critical_output_rules.dart';
import 'package:portfolio_assistant/features/genui_core/widgets/guarded_catalog_widget.dart';

const _riskEnum = ['low', 'moderate', 'high'];
const _sentimentEnum = ['bullish', 'bearish', 'neutral'];

final _allocationItemSchema = S.object(
  properties: {
    'ticker': S.string(),
    'amount': S.number(),
    'percent': S.number(),
    'rationale': S.string(),
  },
  required: ['ticker', 'amount', 'percent', 'rationale'],
);

final CatalogItem investmentOpportunityCardItem = CatalogItem(
  name: 'InvestmentOpportunityCard',
  dataSchema: S.object(
    description: 'Opción de inversión recomendada.',
    properties: {
      'ticker': S.string(),
      'companyName': S.string(),
      'currentPrice': S.number(),
      'sector': S.string(),
      'riskLevel': S.string(enumValues: _riskEnum),
      'expectedReturn': S.string(),
      'pros': S.list(items: S.string(), maxItems: 3),
      'cons': S.list(items: S.string(), maxItems: 3),
      'fitScore': S.number(minimum: 0, maximum: 100),
    },
    required: [
      'ticker',
      'companyName',
      'currentPrice',
      'sector',
      'riskLevel',
      'expectedReturn',
      'pros',
      'cons',
      'fitScore',
    ],
  ),
  widgetBuilder: (ctx) => guardedCatalogWidget(
        ctx,
        InvestmentCatalogWidgets.investmentOpportunityCard,
      ),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "InvestmentOpportunityCard",
    "ticker": "MSFT",
    "companyName": "Microsoft Corp.",
    "currentPrice": 415.20,
    "sector": "Technology",
    "riskLevel": "moderate",
    "expectedReturn": "~10-14% anual",
    "pros": ["Crecimiento sostenido en cloud", "Alta liquidez"],
    "cons": ["Valuación elevada respecto al sector"],
    "fitScore": 82
  }
]
''',
  ],
);

final CatalogItem riskProfileSliderItem = CatalogItem(
  name: 'RiskProfileSlider',
  dataSchema: S.object(
    description: 'Slider de perfil de riesgo 0-100.',
    properties: {
      'currentValue': S.number(minimum: 0, maximum: 100),
      'label': S.string(),
      'path': S.string(),
    },
    required: ['currentValue', 'label', 'path'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, InvestmentCatalogWidgets.riskProfileSlider),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "RiskProfileSlider",
    "currentValue": 50,
    "label": "Conservador → Agresivo",
    "path": "/user/risk_profile"
  }
]
''',
  ],
);

final CatalogItem budgetAllocationCardItem = CatalogItem(
  name: 'BudgetAllocationCard',
  dataSchema: S.object(
    description: 'Distribución del presupuesto entre activos.',
    properties: {
      'totalBudget': S.number(),
      'allocations': S.list(items: _allocationItemSchema),
    },
    required: ['totalBudget', 'allocations'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, InvestmentCatalogWidgets.budgetAllocationCard),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "BudgetAllocationCard",
    "totalBudget": 2000,
    "allocations": [
      {
        "ticker": "QQQ",
        "amount": 1200,
        "percent": 60,
        "rationale": "Core tech diversificado"
      },
      {
        "ticker": "VTI",
        "amount": 800,
        "percent": 40,
        "rationale": "Balance mercado amplio"
      }
    ]
  }
]
''',
  ],
);

final CatalogItem marketContextCardItem = CatalogItem(
  name: 'MarketContextCard',
  dataSchema: S.object(
    description: 'Contexto macro relevante.',
    properties: {
      'title': S.string(),
      'summary': S.string(),
      'sentiment': S.string(enumValues: _sentimentEnum),
      'relevance': S.string(),
    },
    required: ['title', 'summary', 'sentiment', 'relevance'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, InvestmentCatalogWidgets.marketContextCard),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "MarketContextCard",
    "title": "Tech en rally moderado",
    "summary": "El sector tecnológico muestra momentum positivo con volatilidad controlada.",
    "sentiment": "bullish",
    "relevance": "Aplica a tu interés en tech moderado"
  }
]
''',
  ],
);

final CatalogItem investmentConfirmCardItem = CatalogItem(
  name: 'InvestmentConfirmCard',
  dataSchema: S.object(
    description: 'Confirmación final de la inversión.',
    properties: {
      'ticker': S.string(),
      'shares': S.number(),
      'pricePerShare': S.number(),
      'totalAmount': S.number(),
      'confirmEvent': S.string(),
    },
    required: ['ticker', 'shares', 'pricePerShare', 'totalAmount', 'confirmEvent'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, InvestmentCatalogWidgets.investmentConfirmCard),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "InvestmentConfirmCard",
    "ticker": "QQQ",
    "shares": 2.85,
    "pricePerShare": 420.50,
    "totalAmount": 1200,
    "confirmEvent": "investment_confirmed"
  }
]
''',
  ],
);

const String _investmentRules = '''
INVESTMENT DECISION RULES:

1. If the user message doesn't include a budget amount, ALWAYS ask for it first before showing options.

2. NEVER show more than 4 InvestmentOpportunityCards at once.

3. Include RiskProfileSlider when:
   - The user has no defined risk profile (/user/risk_profile is null)
   - The user requests something that doesn't match their current profile
   - The user explicitly asks to adjust their risk tolerance

4. Always check /portfolio/sectors to avoid over-concentration. If the user already has >40% in one sector, warn them with an AlertBanner before showing options in that sector.

5. Include MarketContextCard when there is relevant macro context for the decision.

6. BudgetAllocationCard is required when suggesting 2+ assets.

7. ALWAYS end with InvestmentConfirmCard as the final step.

8. fitScore must reflect risk alignment, sector diversification and budget fit.

9. pros and cons must be balanced. Never all pros or all cons.

10. CRITICAL FOR GPT-4o: Always respond with valid JSON strictly following the catalog schemas. Do not add extra fields, do not omit required fields, do not wrap the JSON in markdown code blocks. Respond ONLY with raw JSON. No explanations, no markdown, no code blocks. Raw JSON only.

Use catalogId "https://a2ui.org/specification/v0_9/standard_catalog.json" in createSurface messages.
Compose surfaces using a Column as root with child component IDs when showing multiple widgets.
''';

/// Catálogo del flujo de decisión de inversión.
///
/// Los items base (Column, Text, etc.) vienen de [BasicCatalogItems] del SDK.
abstract final class InvestmentCatalog {
  static Catalog build() {
    final base = BasicCatalogItems.asCatalog();
    return base.copyWith(
      newItems: [
        investmentOpportunityCardItem,
        riskProfileSliderItem,
        budgetAllocationCardItem,
        marketContextCardItem,
        investmentConfirmCardItem,
        alertBannerItem,
      ],
      systemPromptFragments: [
        criticalOutputFormatRules,
        ...base.systemPromptFragments,
        _investmentRules,
      ],
    );
  }
}
