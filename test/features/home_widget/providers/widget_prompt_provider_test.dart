// Reglas de cuándo ofrecer el widget (3.ª apertura, ya instalado, 30 días,
// máximo 2, sin cartera), el contador guardado y los datos de la vista
// previa. Correr: flutter test test/features/home_widget/providers/widget_prompt_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_prompt_provider.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime(2026, 11, 10, 12);

  bool offer({
    int opens = 3,
    int shown = 0,
    DateTime? last,
    bool installed = false,
    bool portfolio = true,
    bool thisOpen = false,
  }) => WidgetPromptRules.shouldOffer(
    opens: opens,
    offersShown: shown,
    lastOfferAt: last,
    now: now,
    installed: installed,
    hasPortfolio: portfolio,
    offeredThisOpen: thisOpen,
  );

  group('WidgetPromptRules.shouldOffer', () {
    test('from the 3rd open, not before', () {
      expect(offer(opens: 2), isFalse);
      expect(offer(opens: 3), isTrue);
      expect(offer(opens: 9), isTrue);
    });

    test('never with a widget installed or without portfolio', () {
      expect(offer(installed: true), isFalse);
      expect(offer(portfolio: false), isFalse);
    });

    test('30 days between offers', () {
      expect(
        offer(shown: 1, last: now.subtract(const Duration(days: 29))),
        isFalse,
      );
      expect(
        offer(shown: 1, last: now.subtract(const Duration(days: 30))),
        isTrue,
      );
    });

    test('at most 2 offers in total', () {
      expect(
        offer(shown: 2, last: now.subtract(const Duration(days: 90))),
        isFalse,
      );
    });

    test('only once per open', () {
      expect(offer(thisOpen: true), isFalse);
    });
  });

  group('WidgetPromptNotifier', () {
    test('counts opens and persists them', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final n = WidgetPromptNotifier(prefs, now: () => now);
      await n.registerOpen();
      await n.registerOpen();
      expect(n.state.opens, 2);
      expect(prefs.getInt(WidgetPrefsKeys.promptOpens), 2);
    });

    test('markShown stores count and date; a new open re-enables it', () async {
      SharedPreferences.setMockInitialValues({WidgetPrefsKeys.promptOpens: 3});
      final prefs = await SharedPreferences.getInstance();
      final n = WidgetPromptNotifier(prefs, now: () => now);
      expect(n.shouldOffer(installed: false, hasPortfolio: true), isTrue);
      await n.markShown();
      expect(n.state.offeredThisOpen, isTrue);
      expect(n.shouldOffer(installed: false, hasPortfolio: true), isFalse);
      expect(prefs.getInt(WidgetPrefsKeys.promptShown), 1);
      expect(
        prefs.getInt(WidgetPrefsKeys.promptLastAt),
        now.millisecondsSinceEpoch,
      );
      // Una apertura más: sigue el cooldown de 30 días.
      await n.registerOpen();
      expect(n.shouldOffer(installed: false, hasPortfolio: true), isFalse);
      // Se reconstruye leyendo lo guardado (reinicio de la app).
      final again = WidgetPromptNotifier(prefs, now: () => now);
      expect(again.state.offersShown, 1);
      expect(again.state.lastOfferAt, now);
    });

    test('promptKeys covers every stored key (cleared on sign-out)', () {
      expect(WidgetPrefsKeys.promptKeys, [
        WidgetPrefsKeys.promptOpens,
        WidgetPrefsKeys.promptShown,
        WidgetPrefsKeys.promptLastAt,
      ]);
    });
  });

  group('WidgetPreviewData.fromSnapshotJson', () {
    test('ready snapshot gives the real texts', () {
      final data = WidgetPreviewData.fromSnapshotJson({
        'state': 'ready',
        'total_text': r'$1.234,00',
        'change_text': r'+$12,00',
        'change_pct_text': '+1,0%',
        'direction': 'up',
        'phrase': 'Tu cartera sube hoy.',
        'period': 'today',
        'labels': {'period_today': 'Hoy', 'hidden_amount': '••••'},
      });
      expect(data!.total, r'$1.234,00');
      expect(data.period, 'Hoy');
      expect(data.direction, 'up');
      expect(data.phrase, 'Tu cartera sube hoy.');
    });

    test('hidden amounts show the dots, never a total', () {
      final data = WidgetPreviewData.fromSnapshotJson({
        'state': 'ready',
        'amounts_hidden': true,
        'change_pct_text': '+1,0%',
        'labels': {'hidden_amount': '••••'},
      });
      expect(data!.total, '••••');
      expect(data.change, isNull);
    });

    test('no data or not ready: null (illustrative view)', () {
      expect(WidgetPreviewData.fromSnapshotJson(null), isNull);
      expect(
        WidgetPreviewData.fromSnapshotJson({'state': 'no_portfolio'}),
        isNull,
      );
    });
  });
}
