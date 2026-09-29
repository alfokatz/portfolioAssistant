import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_follow_up_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_time.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_eps_history_chart.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_media_index.dart';
import 'package:portfolio_assistant/shared/widgets/genui_error_card.dart';

import '../../../helpers/genui_test_helpers.dart';

// La decisión de "qué pregunta rutea a qué widget" la toma el modelo (ver
// explore_prompt_rules_test.dart para las reglas exactas que sigue). Esto
// verifica la capa determinística inmediatamente debajo de esa decisión:
// si el modelo elige QaEarningsCalendar / QaNewsSummary / QaFundamentals
// con el shape de datos que documenta el catálogo, el widget correcto se
// resuelve y renderiza sin caer al fallback de error.
void main() {
  final catalog = AssistantCatalog.build();

  /// Renderiza [name] con [data] arbitraria (casos degenerados), con o sin
  /// [QaFollowUpScope].
  Future<void> pumpData(
    WidgetTester tester,
    String name,
    Map<String, dynamic> data, {
    ValueChanged<String>? onFollowUp,
  }) async {
    final item = catalog.items.firstWhere((i) => i.name == name);
    final component = {'id': 'c', 'component': name, ...data};
    await tester.binding.setSurfaceSize(genuiTestViewportSize);
    Widget body = SingleChildScrollView(
      child: Builder(
        builder:
            (context) => item.widgetBuilder(
              catalogContextFor(
                buildContext: context,
                component: component,
                catalog: catalog,
              ),
            ),
      ),
    );
    if (onFollowUp != null) {
      body = QaFollowUpScope(onFollowUp: onFollowUp, child: body);
    }
    await tester.pumpWidget(genuiTestApp(child: body));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(GenUiErrorCard), findsNothing);
  }

  test('the three widgets are reachable from the assistant catalog', () {
    final names = catalog.items.map((item) => item.name).toSet();
    expect(names, contains('QaEarningsCalendar'));
    expect(names, contains('QaNewsSummary'));
    expect(names, contains('QaFundamentals'));
  });

  group('QaEarningsCalendar', () {
    final item = catalog.items.firstWhere(
      (i) => i.name == 'QaEarningsCalendar',
    );

    testWidgets('next-report example: date, period, timing and estimate', (
      tester,
    ) async {
      await pumpCatalogItemExample(tester, catalog, item, exampleIndex: 0);

      expect(find.text('NVDA'), findsOneWidget);
      expect(find.text('T3 FY26'), findsOneWidget);
      expect(find.text('13 nov 2026'), findsOneWidget);
      expect(find.text('Después del cierre'), findsOneWidget);
      expect(find.text('\$1.28'), findsOneWidget);
      expect(find.byType(QaEpsHistoryChart), findsNothing);
    });

    testWidgets('latest-result example: EPS actual vs. estimate + beat tag', (
      tester,
    ) async {
      await pumpCatalogItemExample(tester, catalog, item, exampleIndex: 1);

      expect(find.textContaining('3.30'), findsOneWidget);
      expect(find.textContaining('3.10'), findsOneWidget);
      expect(find.text('Superó'), findsOneWidget);
      expect(find.textContaining('24 jul 2026'), findsOneWidget);
    });

    testWidgets('full example: next report + EPS history chart + miss', (
      tester,
    ) async {
      await pumpCatalogItemExample(tester, catalog, item, exampleIndex: 2);

      expect(find.text('20 oct 2026'), findsOneWidget);
      expect(find.byType(QaEpsHistoryChart), findsOneWidget);
      for (final q in ['T3 FY25', 'T4 FY25', 'T1 FY26', 'T2 FY26']) {
        expect(find.text(q), findsOneWidget);
      }
      expect(find.text('No alcanzó'), findsOneWidget);
    });

    testWidgets('history without latest fields falls back to newest quarter', (
      tester,
    ) async {
      await pumpData(tester, 'QaEarningsCalendar', {
        'ticker': 'AAPL',
        'history': [
          {'periodLabel': 'T1 FY26', 'epsActual': 1.5, 'epsEstimate': 1.6},
          {'periodLabel': 'T2 FY26', 'epsActual': 1.7, 'epsEstimate': 1.5},
        ],
      });
      expect(find.text('Superó'), findsOneWidget);
      expect(find.textContaining('Último reporte · T2 FY26'), findsOneWidget);
    });

    testWidgets('degenerate: only a ticker, garbage history', (tester) async {
      await pumpData(tester, 'QaEarningsCalendar', {
        'ticker': 'XYZ',
        'history': [
          {'periodLabel': 'T1', 'epsActual': null},
          'basura',
        ],
      });
      expect(find.text('Sin fechas de reporte disponibles.'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining('NaN'), findsNothing);
    });

    testWidgets('follow-ups hidden without scope, shown and sent with it', (
      tester,
    ) async {
      await pumpData(tester, 'QaEarningsCalendar', {
        'ticker': 'TSLA',
        'nextReportDateLabel': '20 oct 2026',
      });
      expect(find.text('Noticias'), findsNothing);

      final sent = <String>[];
      await pumpData(tester, 'QaEarningsCalendar', {
        'ticker': 'TSLA',
        'nextReportDateLabel': '20 oct 2026',
      }, onFollowUp: sent.add);
      expect(find.text('Earnings'), findsNothing);
      await tester.tap(find.text('Noticias'));
      expect(sent, ['¿Qué noticias hay de TSLA?']);
    });
  });

  group('QaNewsSummary', () {
    final item = catalog.items.firstWhere((i) => i.name == 'QaNewsSummary');

    tearDown(NewsMediaIndex.instance.clear);

    testWidgets('example renders hero + rows with dates and sources', (
      tester,
    ) async {
      await pumpCatalogItemExample(tester, catalog, item, exampleIndex: 0);

      expect(find.text('AAPL'), findsOneWidget);
      expect(find.textContaining('Apple supera expectativas'), findsOneWidget);
      expect(find.textContaining('hace 2 días'), findsOneWidget);
      expect(find.textContaining('Bloomberg'), findsOneWidget);
      // Sin imagen en el índice: ninguna caja de imagen.
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('looks up image and exact time by url (never from the model)', (
      tester,
    ) async {
      NewsMediaIndex.instance.record(
        CompanyNewsItem(
          ticker: 'AAPL',
          headline: 'x',
          summary: '',
          url: 'https://example.com/a',
          source: 'Reuters',
          publishedAt: DateTime.now().subtract(const Duration(hours: 2)),
          imageUrl: 'https://example.com/a.jpg',
        ),
      );
      await pumpData(tester, 'QaNewsSummary', {
        'ticker': 'AAPL',
        'items': [
          {
            'headline': 'Titular',
            'summaryLine': 'Resumen.',
            'dateLabel': '29 sep 2026',
            'source': 'Reuters',
            'url': 'https://example.com/a',
          },
        ],
      });
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Reuters · hace 2 h'), findsOneWidget);
    });

    testWidgets('multi-ticker card uses a generic title and tags rows', (
      tester,
    ) async {
      await pumpData(tester, 'QaNewsSummary', {
        'ticker': 'AAPL',
        'items': [
          {
            'headline': 'Uno',
            'summaryLine': 's',
            'dateLabel': 'hoy',
            'ticker': 'AAPL',
          },
          {
            'headline': 'Dos',
            'summaryLine': 's',
            'dateLabel': 'ayer',
            'ticker': 'MSFT',
          },
        ],
      });
      expect(find.text('Noticias'), findsOneWidget);
      expect(find.text('AAPL · MSFT'), findsOneWidget);
      expect(find.text('MSFT · ayer'), findsOneWidget);
    });

    testWidgets('degenerate: empty items does not throw', (tester) async {
      await pumpData(tester, 'QaNewsSummary', {'ticker': 'AAPL', 'items': []});
      expect(find.text('No hay noticias recientes.'), findsOneWidget);
    });

    testWidgets('follow-ups exclude news', (tester) async {
      final sent = <String>[];
      await pumpData(tester, 'QaNewsSummary', {
        'ticker': 'AAPL',
        'items': [
          {'headline': 'Uno', 'summaryLine': 's', 'dateLabel': 'hoy'},
        ],
      }, onFollowUp: sent.add);
      expect(find.text('Gráfico'), findsOneWidget);
      expect(find.text('Earnings'), findsOneWidget);
      await tester.tap(find.text('Earnings'));
      expect(sent.single, contains('AAPL'));
    });
  });

  group('QaFundamentals', () {
    final item = catalog.items.firstWhere((i) => i.name == 'QaFundamentals');

    testWidgets('example: market cap hero, grouped sections, 52w range', (
      tester,
    ) async {
      await pumpCatalogItemExample(tester, catalog, item, exampleIndex: 0);

      expect(find.text('AAPL'), findsOneWidget);
      expect(find.text('Technology'), findsOneWidget);
      expect(find.text('38,6x'), findsOneWidget);
      expect(find.text('\$4,98T'), findsOneWidget);
      expect(find.text('VALUACIÓN'), findsOneWidget);
      expect(find.text('RENTABILIDAD'), findsOneWidget);
      expect(find.text('DIVIDENDO'), findsOneWidget);
      expect(find.text('RANGO 52 SEMANAS'), findsOneWidget);
      // Barras solo en márgenes/ROE, no en el dividend yield.
      expect(find.byType(QaProgressBar), findsNWidgets(2));
    });

    testWidgets('infers groups from labels when the model omits them', (
      tester,
    ) async {
      await pumpData(tester, 'QaFundamentals', {
        'ticker': 'MSFT',
        'items': [
          {'label': 'P/E (TTM)', 'value': '28,0×'},
          {'label': 'Margen bruto', 'value': '67,94%'},
          {'label': 'Beta', 'value': '0,9'},
        ],
        'week52Low': 300,
        'week52High': 500,
        'currentPrice': 450,
      });
      expect(find.text('VALUACIÓN'), findsOneWidget);
      expect(find.text('RENTABILIDAD'), findsOneWidget);
      expect(find.text('OTROS'), findsOneWidget);
      expect(find.byType(QaRangeBar), findsOneWidget);
      expect(find.text('A 10.0% del máximo'), findsOneWidget);
    });

    testWidgets('degenerate: bad range and empty items render cleanly', (
      tester,
    ) async {
      await pumpData(tester, 'QaFundamentals', {
        'ticker': 'X',
        'items': [
          {'label': '', 'value': ''},
        ],
        'week52Low': 10,
        'week52High': 5,
      });
      expect(find.byType(QaRangeBar), findsNothing);
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('follow-ups exclude fundamentals', (tester) async {
      await pumpData(tester, 'QaFundamentals', {
        'ticker': 'MSFT',
        'items': [
          {'label': 'Beta', 'value': '0,9'},
        ],
      }, onFollowUp: (_) {});
      expect(find.text('Fundamentals'), findsNothing);
      expect(find.text('Noticias'), findsOneWidget);
    });
  });

  group('QaTime', () {
    final now = DateTime(2026, 9, 29, 15);

    test('ago: minutes, hours, yesterday, days, absolute date', () {
      expect(
        QaTime.ago(now.subtract(const Duration(minutes: 5)), now: now),
        'hace 5 min',
      );
      expect(
        QaTime.ago(now.subtract(const Duration(hours: 2)), now: now),
        'hace 2 h',
      );
      expect(QaTime.ago(DateTime(2026, 9, 28, 20), now: now), 'ayer');
      expect(QaTime.ago(DateTime(2026, 9, 25), now: now), 'hace 4 días');
      expect(QaTime.ago(DateTime(2026, 9, 10), now: now), '10 sep');
      expect(QaTime.ago(DateTime(2025, 12, 1), now: now), '1 dic 2025');
    });

    test('countdown: today, tomorrow, N days, past → null', () {
      expect(QaTime.countdown(DateTime(2026, 9, 29), now: now), 'hoy');
      expect(QaTime.countdown(DateTime(2026, 9, 30), now: now), 'mañana');
      expect(QaTime.countdown(DateTime(2026, 10, 20), now: now), 'en 21 días');
      expect(QaTime.countdown(DateTime(2026, 9, 1), now: now), isNull);
    });
  });
}
