// Capturas de la app real para los anuncios (scripts/ads/ads.json): el inicio
// con la cartera, el diagnóstico con Tecnología pesando de más y el chat
// respondiendo preguntas variadas (por qué bajé, comprar, vender, metas,
// jubilación, ETFs, resultados, noticias, alertas, conectar un bróker…).
// Pantallas, widgets y turnos reales (tools y cards de verdad) con una
// cartera de demo; lo único falso es el modelo. Tema claro, iPhone Pro.
// No corre en la suite normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=ads-out/screens \
//     flutter test test/screenshots/ads_screenshots_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dartz/dartz.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
// Viene con el SDK (y con easy_localization); solo para estos screenshots.
// ignore: depend_on_referenced_packages
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/entities/earnings_calendar_entry.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/entities/subscription_status.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/closed_position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/domain/repositories/investor_profile_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/repositories/subscription_repository.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_tracker.dart';
import 'package:portfolio_assistant/domain/use_cases/delete_positions_by_ticker_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_benchmark_comparison_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_history_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_summary_use_case.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_deps.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/services/company_brand_loader.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/assistant_screen.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_composer_field.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';
import 'package:portfolio_assistant/features/investor_profile/providers/investor_profile_provider.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/domain/portfolio_diagnosis.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/providers/portfolio_diagnosis_provider.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/view/portfolio_diagnosis_screen.dart';
import 'package:portfolio_assistant/features/subscription/providers/revenue_cat_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/home_app_bar.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/portfolio_hero_section.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/positions_section.dart';
import 'package:portfolio_assistant/presentation/flows/home/utils/home_chart_utils.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/assistant/fakes/assistant_fakes.dart';

final _out = Platform.environment['SCREENSHOTS_OUT'] ?? 'build/screenshots';
final _enabled = Platform.environment['RUN_SCREENSHOTS'] == '1';

// iPhone Pro: los anuncios meten la captura en un marco de celular.
const _size = Size(402, 874);
const _dpr = 3.0;
final _now = DateTime(2026, 10, 30);

Future<void> _loadAssets() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        File(f).readAsBytes().then((b) => ByteData.view(b.buffer)),
      );
    }
    await loader.load();
  }

  final sdk =
      Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/Development/flutter';
  await load('MaterialIcons', [
    '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
  const weights = {'Regular': 400, 'Medium': 500, 'SemiBold': 600, 'Bold': 700};
  for (final MapEntry(key: name, value: w) in weights.entries) {
    final file = 'assets/fonts/PlusJakartaSans-$name.ttf';
    await load('PlusJakartaSans_${w == 400 ? 'regular' : w}', [file]);
    await load('Plus Jakarta Sans', [file]);
  }
  final es =
      jsonDecode(File('assets/translations/es-ES.json').readAsStringSync())
          as Map<String, dynamic>;
  Localization.load(const Locale('es', 'ES'), translations: Translations(es));
  // Sin fijar Intl.defaultLocale, igual que la app: los dólares salen
  // "$12,480.00" (ver AppNumberFormat).
  await initializeDateFormatting('es_ES');
}

void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = _size * _dpr;
  tester.view.devicePixelRatio = _dpr;
  tester.view.padding = const FakeViewPadding(
    top: 47 * _dpr,
    bottom: 34 * _dpr,
  );
  tester.view.viewPadding = const FakeViewPadding(
    top: 47 * _dpr,
    bottom: 34 * _dpr,
  );
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

/// La app como en el teléfono: tema claro real, español y el halo de fondo
/// que el shell pinta detrás de todas las pantallas.
Widget _app({required Widget home, ProviderContainer? container}) {
  final themes = ProviderContainer();
  final theme = themes.read(themeDataLightProvider);
  themes.dispose();
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('es', 'ES')],
    locale: const Locale('es', 'ES'),
    builder:
        (context, child) => Stack(
          children: [
            const Positioned.fill(child: AppBackgroundGradient()),
            child!,
          ],
        ),
    home: home,
  );
  return container == null
      ? ProviderScope(
        overrides: [
          companyBrandLoaderProvider.overrideWithValue(
            CompanyBrandLoader(_NoBrands()),
          ),
        ],
        child: app,
      )
      : UncontrolledProviderScope(container: container, child: app);
}

Future<void> _settle(WidgetTester tester, {int rounds = 30}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() async {});
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String id,
) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image =
      (await tester.runAsync(() => render.toImage(pixelRatio: _dpr)))!;
  final bytes =
      (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      ))!;
  File('$_out/$id.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}

// ------------------------------------------------------------ cartera demo

/// [value] es el valor de la posición; [qty] acciones a value / qty cada una.
PositionValuation _pos(
  String ticker,
  double value, {
  double gain = 1,
  double qty = 1,
}) => PortfolioCalculator.valuate(
  position: Position(
    id: ticker,
    ticker: ticker,
    quantity: qty,
    purchasePrice: value / gain / qty,
    purchaseDate: DateTime(2025, 2, 3),
  ),
  currentPrice: value / qty,
);

/// Cartera de demo (inicio y chat): $12,480 en total.
final _homePositions = [
  _pos('VOO', 4680, gain: 1.18, qty: 8),
  _pos('NVDA', 3150, gain: 1.42, qty: 18),
  _pos('AAPL', 2050, gain: 1.09, qty: 8),
  _pos('MSFT', 1600, gain: 0.97, qty: 3),
  _pos('KO', 1000, gain: 1.05, qty: 14),
];

PortfolioSummary _summary(List<PositionValuation> valuations) {
  final value = valuations.fold(0.0, (s, v) => s + v.marketValue);
  final cost = valuations.fold(
    0.0,
    (s, v) => s + v.position.purchasePrice * v.position.quantity,
  );
  return PortfolioSummary(
    totalValue: value,
    totalCostBasis: cost,
    totalPnlAbsolute: value - cost,
    totalPnlPercent: (value - cost) / cost * 100,
    valuations: valuations,
  );
}

/// Un mes que sube y baja (nunca solo sube) y termina en [end], +1,3 %.
List<PortfolioHistoryPoint> _monthHistory(double end, double cost) {
  const wave = [
    0.0, 0.4, -0.3, -0.9, -0.5, 0.2, 0.8, 0.5, -0.2, -0.6, //
    -0.1, 0.6, 1.1, 0.7, 0.3, 0.9, 1.4, 1.0, 0.6, 1.2, //
    1.7, 1.3, 0.9, 1.5, 1.9, 1.6, 1.1, 1.4, 1.7, 1.3,
  ];
  final start = end / 1.013;
  return [
    for (final (i, w) in wave.indexed)
      PortfolioHistoryPoint(
        date: _now.subtract(Duration(days: wave.length - 1 - i)),
        totalValue: i == wave.length - 1 ? end : start * (1 + w / 100),
        totalCostBasis: cost,
      ),
  ];
}

// ----------------------------------------------------------- diagnóstico

List<PriceCandle> _sp(double start, double end) {
  final from = DateTime(2025, 1, 1);
  final days = _now.difference(from).inDays;
  return [
    for (var i = 0; i <= days; i++)
      PriceCandle(
        date: from.add(Duration(days: i)),
        close: start + (end - start) * i / days,
      ),
  ];
}

/// Cartera del anuncio 7: Tecnología pesa más del 40 % contando los ETFs.
PortfolioDiagnosis _concentratedDiagnosis() {
  final positions = [
    _pos('NVDA', 2900, gain: 1.9),
    _pos('QQQ', 3300, gain: 1.12),
    _pos('AAPL', 1900, gain: 1.1),
    _pos('VOO', 2400, gain: 1.08),
    _pos('JNJ', 1500, gain: 1.04),
  ];
  return PortfolioDiagnosisBuilder.build(
    DiagnosisInputs(
      valuations: positions,
      lots: positions,
      sectorByTicker: const {
        'NVDA': 'Tecnología',
        'AAPL': 'Tecnología',
        'JNJ': 'Salud',
      },
      funds: const {
        'QQQ': FundLook(
          holdings: {'NVDA': 9.1, 'AAPL': 8.2, 'MSFT': 7.9},
          sectors: {'Tecnología': 61, 'Consumo cíclico': 18},
          expenseRatioPct: 0.2,
          stockPct: 100,
        ),
        'VOO': FundLook(
          holdings: {'NVDA': 7.2, 'AAPL': 6.6, 'MSFT': 6.1},
          sectors: {'Tecnología': 33, 'Finanzas': 13, 'Salud': 10},
          expenseRatioPct: 0.03,
          stockPct: 99.5,
        ),
      },
      sp500: _sp(100, 112),
      now: _now,
    ),
  );
}

// ------------------------------------------------------------------ chat

String _textOf(Map m) {
  final content = m['content'];
  if (content is String) return content;
  return (content as List).map((c) => (c as Map)['text'] ?? '').join();
}

String _surfaceIdOf(Map<String, dynamic> body) {
  final messages = (body['messages'] as List).cast<Map>();
  final lastUser = messages.lastWhere((m) => m['role'] == 'user');
  return RegExp(
    r'SURFACE_ID[^:]*: (\S+)',
  ).firstMatch(_textOf(lastUser))!.group(1)!;
}

/// El ejemplo del catálogo de una card que trae sus propios datos.
Map<String, Object?> _example(String component) {
  final item = AssistantCatalog.build().items.firstWhere(
    (i) => i.name == component,
  );
  final list = jsonDecode(item.exampleData.first()) as List;
  return Map<String, Object?>.from(
    list.cast<Map>().firstWhere((c) => c['component'] == component),
  );
}

/// Una pregunta a Porty: las tools que llamaría el modelo (corren de verdad)
/// y la respuesta. En [cards], "{{clave}}" se reemplaza por ese campo del
/// resultado de la última tool que lo trae (proposal_id, plan_id…).
class _Chat {
  const _Chat(
    this.id,
    this.question,
    this.text,
    this.cards, {
    this.calls = const [],
  });

  final String id;
  final String question;
  final List<(String, Map<String, Object?>)> calls;

  /// Sin cifras: las muestran las cards, y el chequeo de la app borra las
  /// que no salen de los datos del turno.
  final String text;
  final List<Map<String, Object?>> cards;
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final _today = _ymd(DateTime.now());

final _chats = <_Chat>[
  const _Chat(
    'ad01_chat_por_que_bajo',
    '¿Por qué bajé hoy?',
    'Hoy bajaste sobre todo por NVDA, que cayó después de presentar su '
        'reporte. El resto de tu cartera está estable.',
    [
      {
        'component': 'QaTopMovers',
        'periodLabel': 'hoy',
        'best': {'ticker': 'VOO', 'changePct': 0.4},
        'worst': {'ticker': 'NVDA', 'changePct': -4.8},
      },
    ],
  ),
  const _Chat(
    'chat_concentracion',
    '¿Estoy muy concentrado?',
    'Un poco: entre VOO y NVDA tenés más de la mitad de tu cartera. VOO ya '
        'está repartido en muchas empresas, así que el peso fuerte es NVDA.',
    [
      {
        'component': 'QaConcentrationBar',
        'title': 'Concentración por activo',
        'items': [
          {'ticker': 'VOO', 'weightPct': 37.5, 'isHighlighted': true},
          {'ticker': 'NVDA', 'weightPct': 25.2, 'isHighlighted': true},
          {'ticker': 'AAPL', 'weightPct': 16.4, 'isHighlighted': false},
          {'ticker': 'MSFT', 'weightPct': 12.8, 'isHighlighted': false},
          {'ticker': 'KO', 'weightPct': 8.0, 'isHighlighted': false},
        ],
      },
    ],
  ),
  _Chat(
    'chat_compra',
    'Compré 5 VOO hoy',
    'Listo, lo preparé. Revisá los datos y confirmá para sumarlo a tu cartera.',
    const [
      {'component': 'QaActionProposal', 'proposalId': '{{proposal_id}}'},
    ],
    calls: [
      ('propose_buy', {'ticker': 'VOO', 'shares': 5, 'date': _today}),
    ],
  ),
  _Chat(
    'chat_venta',
    'Vendí 2 NVDA a 180 dólares',
    'Anotado. Revisá la venta y confirmala: te queda el resto de tu NVDA.',
    const [
      {'component': 'QaActionProposal', 'proposalId': '{{proposal_id}}'},
    ],
    calls: [
      (
        'propose_sell',
        {'ticker': 'NVDA', 'shares': 2, 'price_usd': 180, 'date': _today},
      ),
    ],
  ),
  const _Chat(
    'chat_alerta_precio',
    'Avisame si NVDA baja de 150',
    'Dale, te aviso apenas NVDA cruce ese precio. Confirmá la alerta.',
    [
      {'component': 'QaActionProposal', 'proposalId': '{{proposal_id}}'},
    ],
    calls: [
      (
        'propose_price_alert',
        {'ticker': 'NVDA', 'condition': 'below', 'target': 150},
      ),
    ],
  ),
  const _Chat(
    'chat_conectar_broker',
    'Quiero conectar mi cuenta de Interactive Brokers',
    'Buenísimo: así tus posiciones se actualizan solas. Es solo lectura, '
        'nunca opero por vos.',
    [
      {'component': 'QaActionProposal', 'proposalId': '{{proposal_id}}'},
    ],
    calls: [
      ('propose_broker_action', {'broker': 'snaptrade', 'action': 'connect'}),
    ],
  ),
  const _Chat(
    'chat_meta_viaje',
    'Quiero juntar 4.000 dólares para viajar a Japón en abril de 2027',
    'Te armé el plan para llegar a tiempo. Si te parece bien, lo guardo en '
        'tus metas.',
    [
      {'component': 'QaSavingsPlan', 'planId': '{{plan_id}}'},
    ],
    calls: [
      (
        'get_goal_projection',
        {
          'target_amount': 4000,
          'target_date': '2027-04-30',
          'goal_label': 'Viaje a Japón',
          'goal_type': 'purchase',
        },
      ),
    ],
  ),
  _Chat(
    'chat_jubilacion',
    'Quiero jubilarme en 25 años cobrando 3.000 por mes',
    'Te muestro cuánto te haría falta y cuánto ahorrar por mes para '
        'llegar, con tu cartera de hoy como punto de partida.',
    const [
      {'component': 'QaSavingsPlan', 'planId': '{{plan_id}}'},
    ],
    calls: [
      (
        'get_goal_projection',
        {
          'desired_monthly_income': 3000,
          'target_date': _ymd(
            DateTime.now().add(const Duration(days: 365 * 25)),
          ),
          'goal_label': 'Jubilación',
          'is_retirement': true,
          'goal_type': 'retirement',
        },
      ),
    ],
  ),
  const _Chat(
    'chat_etf_qqq',
    '¿Qué hay adentro de QQQ?',
    'QQQ sigue a las empresas no financieras más grandes del Nasdaq: es '
        'casi todo tecnología.',
    [
      {'component': 'QaEtfHoldings', 'ticker': 'QQQ'},
    ],
    calls: [
      (
        'get_etf_holdings',
        {
          'tickers': ['QQQ'],
        },
      ),
    ],
  ),
  const _Chat(
    'chat_que_es_un_etf',
    '¿Qué es un ETF?',
    'Es una canasta de acciones que comprás de una sola vez, como si fuera '
        'una acción. Vos ya tenés uno: VOO, que sigue a las empresas más '
        'grandes de EE. UU. Así repartís el riesgo sin elegir empresa por '
        'empresa.',
    [],
  ),
  _Chat(
    'chat_resultados',
    '¿Cuándo presenta resultados NVDA?',
    'NVDA presenta su próximo reporte después del cierre. Esos días el '
        'precio suele moverse más de lo normal.',
    [_example('QaEarningsCalendar')],
    calls: const [
      (
        'get_earnings',
        {
          'tickers': ['NVDA'],
        },
      ),
    ],
  ),
  _Chat(
    'chat_noticias',
    '¿Qué pasó con Apple?',
    'Estas son las noticias más recientes de Apple.',
    [_example('QaNewsSummary')],
    calls: const [
      (
        'get_news',
        {
          'tickers': ['AAPL'],
        },
      ),
    ],
  ),
  _Chat(
    'chat_comparar',
    '¿Cómo vienen Apple y Microsoft este mes?',
    'En el último mes Microsoft viene mejor que Apple.',
    [_example('QaCompareChart')],
    calls: const [
      (
        'get_quote',
        {
          'tickers': ['AAPL', 'MSFT'],
        },
      ),
    ],
  ),
];

/// Lo que vio el modelo de las tools del turno, para llenar "{{clave}}".
Map<String, Object?> _toolResults(Map<String, dynamic> body) {
  final out = <String, Object?>{};
  for (final m in (body['messages'] as List).cast<Map>()) {
    if (m['role'] != 'tool') continue;
    final decoded = jsonDecode(_textOf(m));
    if (decoded is Map) out.addAll(decoded.cast<String, Object?>());
  }
  return out;
}

Map<String, Object?> Function(Map<String, dynamic>) _answerStep(_Chat chat) => (
  body,
) {
  final id = _surfaceIdOf(body);
  final results = _toolResults(body);
  Object? fill(Object? v) => switch (v) {
    String s when s.startsWith('{{') => results[s.substring(2, s.length - 2)],
    Map m => {for (final e in m.entries) e.key: fill(e.value)},
    List l => [for (final x in l) fill(x)],
    _ => v,
  };
  final cards = [
    for (final (i, c) in chat.cards.indexed)
      {...(fill(c)! as Map), 'id': 'c$i'},
  ];
  final update = jsonEncode({
    'version': 'v0.9',
    'updateComponents': {
      'surfaceId': id,
      'components': [
        {
          'id': 'root',
          'component': 'Column',
          'children': ['t', for (final c in cards) c['id']],
        },
        {'id': 't', 'component': 'QaAnswerText', 'text': chat.text},
        ...cards,
      ],
    },
  });
  return textReply(
    '{"version":"v0.9","createSurface":{"surfaceId":"$id",'
    '"catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}\n'
    '$update',
  );
};

/// QQQ como lo manda Yahoo: casi todo tecnología.
Map<String, dynamic> _qqqSummary() {
  final q = etfQuoteSummary(
    name: 'Invesco QQQ Trust',
    holdings: const [
      ('NVDA', 'NVIDIA Corp', 0.091),
      ('MSFT', 'Microsoft Corp', 0.079),
      ('AAPL', 'Apple Inc', 0.082),
    ],
  );
  (q['topHoldings'] as Map)['sectorWeightings'] = [
    {
      'technology': {'raw': 0.61},
    },
    {
      'consumer_cyclical': {'raw': 0.18},
    },
    {
      'communication_services': {'raw': 0.12},
    },
  ];
  (q['fundProfile'] as Map)
    ..['family'] = 'Invesco'
    ..['categoryName'] = 'Large Growth'
    ..['feesExpensesInvestment'] = {
      'annualReportExpenseRatio': {'raw': 0.002},
    };
  return q;
}

ProviderContainer _chatContainer(ScriptedOpenAi api) {
  final subscriptions = _GoldSubscription();
  final tracker = AiUsageTracker(repository: subscriptions);
  return ProviderContainer(
    overrides: [
      homeProvider.overrideWith((ref) => _LoadedHome(ref)),
      getClosedPositionsUseCaseProvider.overrideWithValue(_NoClosedPositions()),
      aiUsageTrackerProvider.overrideWithValue(tracker),
      revenueCatServiceProvider.overrideWithValue(_UnusedRevenueCat()),
      subscriptionProvider.overrideWith(
        (ref) => SubscriptionNotifier(
          tracker: tracker,
          authService: _Session(),
          revenueCat: _UnusedRevenueCat(),
        ),
      ),
      investorProfileProvider.overrideWith(
        (ref) => InvestorProfileNotifier(
          repository: _FreshProfileRepository(),
          authService: _Session(),
        ),
      ),
      portyHapticsServiceProvider.overrideWithValue(
        PortyHapticsService(enabled: false, performer: (_) async {}),
      ),
      companyBrandLoaderProvider.overrideWithValue(
        CompanyBrandLoader(_NoBrands()),
      ),
      assistantDepsProvider.overrideWithValue(
        AssistantDeps(
          createService:
              () => AssistantOpenAiService(
                proxy: AiProxyConfig.fixed(
                  Uri.parse('https://proxy.test'),
                  'jwt-test',
                ),
                model: 'gpt-4.1-mini',
                httpClient: api.client,
              ),
          createData:
              () => fakeDataSources(
                quotes: _DemoQuotes(),
                yahoo: FakeYahooProxy(results: {'QQQ': _qqqSummary()}),
                // El mismo reporte que trae el ejemplo de QaEarningsCalendar.
                earnings: FakeEarningsCalendarRepository(
                  next: EarningsCalendarEntry(
                    ticker: 'NVDA',
                    reportDate: DateTime(2026, 11, 13),
                    fiscalQuarter: 3,
                    fiscalYear: 2026,
                    epsEstimate: 1.28,
                    hour: 'amc',
                  ),
                ),
              ),
        ),
      ),
    ],
  );
}

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    PortyAvatar.ambientMotion = false;
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  for (final chat in _chats) {
    testWidgets(chat.id, (tester) async {
      await tester.runAsync(_loadAssets);
      _phoneView(tester);
      final api = ScriptedOpenAi([
        for (final (i, (name, args)) in chat.calls.indexed)
          (_) => toolCallsReply([('call_$i', name, args)]),
        _answerStep(chat),
      ]);
      final container = _chatContainer(api);
      addTearDown(container.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: _app(container: container, home: const AssistantScreen()),
        ),
      );
      await _settle(tester, rounds: 5);
      await tester.enterText(find.byType(TextField), chat.question);
      await tester.pump();
      await tester.tap(find.byType(AssistantSendButton));
      await _settle(tester, rounds: 120);
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(tester, rounds: 10);
      await _capture(tester, boundary, chat.id);
    }, skip: !_enabled);
  }

  testWidgets('ad02_inicio_cartera', (tester) async {
    await tester.runAsync(_loadAssets);
    _phoneView(tester);
    final summary = _summary(_homePositions);
    final history = _monthHistory(summary.totalValue, summary.totalCostBasis);
    final period = HomeChartUtils.periodPnlFromHistory(history);
    final valuations = List<PositionValuation>.from(summary.valuations)
      ..sort((a, b) => b.pnlAbsolute.compareTo(a.pnlAbsolute));
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: _app(
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              bottom: false,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const HomeAppBar(firstName: 'Sofi'),
                        PortfolioHeroSection(
                          summary: summary,
                          history: history,
                          periodPnlAbsolute: period.absolute,
                          periodPnlPercent: period.percent,
                          selectedRange: ChartTimeRange.m1,
                          onRangeSelected: (_) {},
                        ),
                        const SizedBox(height: AppDimens.sectionGap),
                        PositionsSection(valuations: valuations),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    await _capture(tester, boundary, 'ad02_inicio_cartera');
  }, skip: !_enabled);

  testWidgets('ad07_diagnostico_concentracion', (tester) async {
    await tester.runAsync(_loadAssets);
    _phoneView(tester);
    final diagnosis = _concentratedDiagnosis();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ProviderScope(
          overrides: [
            portfolioDiagnosisProvider.overrideWith((ref) async => diagnosis),
          ],
          child: _app(home: const PortfolioDiagnosisScreen()),
        ),
      ),
    );
    await _settle(tester);
    await _capture(tester, boundary, 'ad07_diagnostico_concentracion');
  }, skip: !_enabled);
}

// ----------------------------------------------------------------- fakes

class _GoldSubscription implements SubscriptionRepository {
  var _used = 40;

  @override
  Future<SubscriptionStatus> fetchStatus() async => SubscriptionStatus(
    tier: SubscriptionTier.gold,
    queriesUsed: _used,
    queriesLimit: 1000,
    month: '2026-10',
  );

  @override
  Future<bool> consumeQuota(int weight) async {
    _used += weight;
    return true;
  }
}

/// Precios de la cartera de demo (los mismos del inicio) y un año de
/// historia que termina en ellos, con el cambio del último mes indicado.
class _DemoQuotes implements QuoteRepository {
  static const _prices = {
    // ticker: (precio, cambio del último mes en %)
    'VOO': (585.0, 1.1),
    'NVDA': (175.0, 3.2),
    'AAPL': (256.25, -2.0),
    'MSFT': (533.33, 1.4),
    'KO': (71.43, 0.6),
    'QQQ': (612.0, 2.1),
  };

  (double, double) _of(String ticker) => _prices[ticker] ?? (100.0, 0.0);

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async =>
      Right(_of(ticker).$1);

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async {
    final (price, month) = _of(ticker);
    final monthAgo = price / (1 + month / 100);
    final end = DateTime(_now.year, _now.month, _now.day);
    return Right([
      for (var i = 0; i < 400; i++)
        PriceCandle(
          date: end.subtract(Duration(days: 399 - i)),
          // Plano con ondas hasta hace un mes; después, derecho al precio.
          close:
              i < 370
                  ? monthAgo * (0.9 + 0.1 * i / 370)
                  : monthAgo + (price - monthAgo) * (i - 369) / 30,
        ),
    ]);
  }

  @override
  Future<List<PriceCandle>> getIntradayCandles(String ticker) async => const [];
}

class _NoBrands implements CompanyBrandRepository {
  @override
  Future<CompanyBrand?> getBrand(String ticker) async => null;
}

class _Session implements SupabaseAuthService {
  @override
  Session? get currentSession => Session(
    accessToken: 'token',
    tokenType: 'bearer',
    user: const User(
      id: 'user',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Unused {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected call: ${invocation.memberName}');
}

class _UnusedRevenueCat extends _Unused implements RevenueCatService {}

class _UnusedSummaryUseCase extends _Unused
    implements GetPortfolioSummaryUseCase {}

class _UnusedHistoryUseCase extends _Unused
    implements GetPortfolioHistoryUseCase {}

class _UnusedBenchmarkUseCase extends _Unused
    implements GetBenchmarkComparisonUseCase {}

class _UnusedDeleteUseCase extends _Unused
    implements DeletePositionsByTickerUseCase {}

class _UnusedClosedRepository extends _Unused
    implements ClosedPositionRepository {}

/// Perfil vigente: la respuesta lleva solo el disclaimer.
class _FreshProfileRepository extends _Unused
    implements InvestorProfileRepository {
  @override
  Future<InvestorProfile?> fetch() async => InvestorProfile(
    risk: RiskTolerance.moderate,
    horizon: InvestmentHorizon.long,
    objective: InvestmentObjective.growth,
    updatedAt: DateTime.now(),
  );
}

class _NoClosedPositions extends GetClosedPositionsUseCase {
  _NoClosedPositions() : super(repository: _UnusedClosedRepository());

  @override
  Future<Either<HttpError, List<ClosedPosition>>> call({void params}) async =>
      const Right([]);
}

/// El chat lee la cartera de la Home: la misma de demo del anuncio 2.
class _LoadedHome extends HomeProvider {
  _LoadedHome(Ref ref)
    : super(
        ref: ref,
        getPortfolioSummaryUseCase: _UnusedSummaryUseCase(),
        getPortfolioHistoryUseCase: _UnusedHistoryUseCase(),
        getBenchmarkComparisonUseCase: _UnusedBenchmarkUseCase(),
        deletePositionsByTickerUseCase: _UnusedDeleteUseCase(),
        getClosedPositionsUseCase: _NoClosedPositions(),
      ) {
    state = HomeState(summary: _summary(_homePositions));
  }
}
