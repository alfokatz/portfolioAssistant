import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/domain/portfolio_diagnosis.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/providers/portfolio_diagnosis_provider.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/view/portfolio_diagnosis_screen.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/view/widgets/diagnosis_entry_card.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';

ThemeData get _light => ProviderContainer().read(themeDataLightProvider);

const _diagnosis = PortfolioDiagnosis(
  findings: [
    DiagnosisFinding(
      kind: DiagnosisKind.overlap,
      tone: DiagnosisTone.attention,
      score: 70,
      ticker: 'NVDA',
      via: ['QQQ', 'VOO'],
      numbers: {'total': 17, 'direct': 10},
    ),
    DiagnosisFinding(
      kind: DiagnosisKind.topHolding,
      tone: DiagnosisTone.attention,
      score: 40,
      ticker: 'VOO',
      numbers: {'pct': 50},
    ),
  ],
  positions: 3,
  funds: 2,
);

class _Seen extends DiagnosisSeenNotifier {
  _Seen(bool seen) : super(null, null) {
    state = seen;
  }
  int marks = 0;

  @override
  Future<void> markSeen() async {
    marks++;
    state = true;
  }
}

class _Home extends StateNotifier<HomeState> implements HomeProvider {
  _Home(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

HomeState _homeWith(int positions) => HomeState(
  loading: false,
  summary: PortfolioSummary(
    totalValue: 1000.0 * positions,
    totalCostBasis: 1000.0 * positions,
    totalPnlAbsolute: 0,
    totalPnlPercent: 0,
    valuations: [
      for (var i = 0; i < positions; i++)
        PortfolioCalculator.valuate(
          position: Position(
            id: '$i',
            ticker: 'T$i',
            quantity: 1,
            purchasePrice: 1000,
            purchaseDate: DateTime(2025),
          ),
          currentPrice: 1000,
        ),
    ],
  ),
);

void main() {
  setUp(() => PortyAvatar.ambientMotion = false);
  tearDown(() => PortyAvatar.ambientMotion = true);

  Future<_Seen> pump(
    WidgetTester tester,
    Future<PortfolioDiagnosis> Function() load,
  ) async {
    final seen = _Seen(false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioDiagnosisProvider.overrideWith((ref) => load()),
          diagnosisSeenProvider.overrideWith((ref) => seen),
        ],
        child: MaterialApp(
          theme: _light,
          home: const PortfolioDiagnosisScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return seen;
  }

  testWidgets('muestra lo que vio, deja preguntas y lo marca como visto', (
    tester,
  ) async {
    final seen = await pump(tester, () async => _diagnosis);
    expect(find.text('diagnosis_porty_many'), findsOneWidget);
    expect(find.text('diagnosis_overlap_title'), findsOneWidget);
    expect(find.text('diagnosis_top_title'), findsOneWidget);
    expect(find.text('diagnosis_overlap_question'), findsOneWidget);
    expect(find.text('diagnosis_top_question'), findsOneWidget);
    expect(find.text('diagnosis_cta_done'), findsOneWidget);
    expect(seen.marks, 1);
  });

  testWidgets('sin datos: Porty lo dice, deja reintentar y no lo marca', (
    tester,
  ) async {
    final seen = await pump(
      tester,
      () async =>
          const PortfolioDiagnosis(findings: [], positions: 0, funds: 0),
    );
    expect(find.text('diagnosis_unavailable'), findsOneWidget);
    expect(find.text('retry'), findsOneWidget);
    expect(seen.marks, 0);
  });

  group('entrada en la Home', () {
    Future<void> pumpEntry(WidgetTester tester, HomeState home, bool seen) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [
              homeProvider.overrideWith((ref) => _Home(home)),
              diagnosisSeenProvider.overrideWith((ref) => _Seen(seen)),
            ],
            child: MaterialApp(
              theme: _light,
              home: const Scaffold(body: DiagnosisEntryCard()),
            ),
          ),
        );

    testWidgets('con cartera y sin haberlo visto, aparece', (tester) async {
      await pumpEntry(tester, _homeWith(3), false);
      expect(find.text('diagnosis_entry_title'), findsOneWidget);
    });

    testWidgets('ya visto o sin cartera, no ocupa lugar', (tester) async {
      await pumpEntry(tester, _homeWith(3), true);
      expect(find.text('diagnosis_entry_title'), findsNothing);
      await pumpEntry(tester, _homeWith(0), false);
      expect(find.text('diagnosis_entry_title'), findsNothing);
    });
  });
}
