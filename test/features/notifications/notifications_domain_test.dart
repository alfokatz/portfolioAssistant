import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/notifications/data/price_alerts_repository.dart';
import 'package:portfolio_assistant/features/notifications/domain/notification_preferences.dart';
import 'package:portfolio_assistant/features/notifications/domain/price_alert.dart';
import 'package:portfolio_assistant/features/notifications/domain/price_alert_form.dart';
import 'package:portfolio_assistant/features/notifications/domain/push_route.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('PushRoute.fromData (el data que arma notify-dispatch)', () {
    test('cada ruta conocida', () {
      expect(PushRoute.fromData({'route': 'home'}), isA<PushRouteHome>());
      expect(
        PushRoute.fromData({'route': 'weekly_report'}),
        isA<PushRouteWeeklyReport>(),
      );
      expect(PushRoute.fromData({'route': 'etoro'}), isA<PushRouteEtoro>());
      expect(
        PushRoute.fromData({'route': 'notification_settings'}),
        isA<PushRouteNotificationSettings>(),
      );
      final ticker =
          PushRoute.fromData({
                'route': 'ticker',
                'ticker': 'VOO',
                'alert_id': 'a1',
              })
              as PushRouteTicker;
      expect(ticker.ticker, 'VOO');
      expect(ticker.alertId, 'a1');
      final ask =
          PushRoute.fromData({
                'route': 'assistant',
                'question': '¿Por qué se mueve NVDA hoy?',
              })
              as PushRouteAssistant;
      expect(ask.question, '¿Por qué se mueve NVDA hoy?');
    });

    test('desconocida o incompleta: null (se abre la app y nada más)', () {
      expect(PushRoute.fromData({'route': 'algo_nuevo'}), isNull);
      expect(PushRoute.fromData({'route': 'ticker'}), isNull);
      expect(PushRoute.fromData({}), isNull);
    });

    test('PushMessage lee kind y log_id', () {
      const m = PushMessage(data: {'kind': 'big_move', 'log_id': '42'});
      expect(m.kind, 'big_move');
      expect(m.logId, 42);
      expect(const PushMessage(data: {}).logId, isNull);
    });
  });

  group('NotificationPreferences', () {
    test('lee la fila de Supabase y vuelve igual', () {
      final prefs = NotificationPreferences.fromRow({
        'enabled': true,
        'price_alerts': false,
        'big_moves': true,
        'portfolio_moves': false,
        'weekly_report': true,
        'earnings': true,
        'service': true,
        'big_move_sensitivity': 'high',
        'quiet_start': '23:30:00',
        'quiet_end': '07:15:00',
        'show_amounts': true,
      });
      expect(prefs.priceAlerts, isFalse);
      expect(prefs.bigMoveSensitivity, BigMoveSensitivity.high);
      expect(prefs.quietStartMinutes, 23 * 60 + 30);
      expect(prefs.quietEndMinutes, 7 * 60 + 15);
      expect(prefs.toRow()['quiet_start'], '23:30');
      expect(NotificationPreferences.fromRow(prefs.toRow()), prefs);
    });

    test('valores raros caen a los defaults de la tabla', () {
      final prefs = NotificationPreferences.fromRow({
        'big_move_sensitivity': 'extrema',
        'quiet_start': '25:99',
        'show_amounts': 'sí',
      });
      expect(prefs, const NotificationPreferences());
      expect(prefs.hasQuietHours, isTrue);
      expect(
        const NotificationPreferences(
          quietStartMinutes: 0,
          quietEndMinutes: 0,
        ).hasQuietHours,
        isFalse,
      );
    });
  });

  group('PriceAlert', () {
    test('precio de disparo y si ya se cumple', () {
      final pct = PriceAlert.fromRow({
        'id': 'a',
        'symbol': 'NVDA',
        'condition': 'pct_down',
        'target': 10,
        'reference_price': 180,
        'repeat': 'daily',
        'status': 'paused',
        'paused_reason': 'plan',
        'created_at': '2026-10-10T12:00:00Z',
      });
      expect(pct.thresholdPrice, closeTo(162, 1e-9));
      expect(pct.isMetBy(161.9), isTrue);
      expect(pct.isMetBy(170), isFalse);
      expect(pct.repeatDaily, isTrue);
      expect(pct.pausedByPlan, isTrue);
      expect(pct.status, PriceAlertStatus.paused);

      final above = PriceAlert.fromRow({
        'id': 'b',
        'symbol': 'VOO',
        'condition': 'above',
        'target': 750,
        'status': 'active',
      });
      expect(above.isMetBy(750), isTrue);
      expect(above.isMetBy(749.99), isFalse);
    });
  });

  group('formulario de alerta', () {
    test('números con coma o punto', () {
      expect(parseUserNumber('750'), 750);
      expect(parseUserNumber(r'$ 1.234,50'), 1234.5);
      expect(parseUserNumber('1,234.50'), 1234.5);
      expect(parseUserNumber('751,2'), 751.2);
      expect(parseUserNumber('10%'), 10);
      expect(parseUserNumber('abc'), isNull);
      expect(parseUserNumber(''), isNull);
    });

    test('no deja crear una alerta que ya se cumple', () {
      final above = buildPriceAlertDraft(
        symbol: 'VOO',
        mode: PriceAlertMode.above,
        input: '700',
        percentUp: false,
        repeatDaily: false,
        currentPrice: 720,
      );
      expect(above.error, PriceAlertFormError.alreadyAbove);
      final below = buildPriceAlertDraft(
        symbol: 'VOO',
        mode: PriceAlertMode.below,
        input: '730',
        percentUp: false,
        repeatDaily: false,
        currentPrice: 720,
      );
      expect(below.error, PriceAlertFormError.alreadyBelow);
    });

    test('arma el borrador', () {
      final ok = buildPriceAlertDraft(
        symbol: 'VOO',
        mode: PriceAlertMode.above,
        input: '750',
        percentUp: false,
        repeatDaily: true,
        currentPrice: 720,
      );
      expect(ok.error, isNull);
      expect(ok.draft!.condition, PriceAlertCondition.above);
      expect(ok.draft!.target, 750);
      expect(ok.draft!.repeatDaily, isTrue);

      final pct = buildPriceAlertDraft(
        symbol: 'NVDA',
        mode: PriceAlertMode.percent,
        input: '10',
        percentUp: false,
        repeatDaily: false,
        currentPrice: 180,
      );
      expect(pct.draft!.condition, PriceAlertCondition.pctDown);
      expect(pct.draft!.referencePrice, 180);
    });

    test('porcentaje: necesita precio y un rango razonable', () {
      PriceAlertFormError? err(String input, double? price) =>
          buildPriceAlertDraft(
            symbol: 'NVDA',
            mode: PriceAlertMode.percent,
            input: input,
            percentUp: true,
            repeatDaily: false,
            currentPrice: price,
          ).error;
      expect(err('10', null), PriceAlertFormError.noPrice);
      expect(err('0.5', 100), PriceAlertFormError.percentRange);
      expect(err('95', 100), PriceAlertFormError.percentRange);
      expect(err('0', 100), PriceAlertFormError.invalidNumber);
    });

    test('sugerencias redondas', () {
      expect(suggestedTarget(720.37, 5), 756);
      expect(suggestedTarget(23.4, -10), 21);
      expect(suggestedTarget(1810, 5), 1900);
      expect(suggestedTarget(4.21, 5), 4.4);
    });
  });

  group('errores del repositorio', () {
    test('tope del plan con el límite en el detalle', () {
      final e = PriceAlertsRepository.mapError(
        const PostgrestException(
          message: 'alert_limit_reached',
          code: 'P0001',
          details: '{"limit" : 1}',
        ),
      );
      expect(e, isA<PriceAlertLimitReached>());
      expect((e as PriceAlertLimitReached).limit, 1);
    });

    test('check e inválidos', () {
      expect(
        PriceAlertsRepository.mapError(
          const PostgrestException(message: 'violates check', code: '23514'),
        ),
        isA<PriceAlertInvalid>(),
      );
      expect(
        PriceAlertsRepository.mapError(
          const PostgrestException(message: 'boom', code: '500'),
        ),
        isA<PriceAlertNetworkError>(),
      );
    });
  });
}
