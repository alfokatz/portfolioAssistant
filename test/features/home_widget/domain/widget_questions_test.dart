// Plantillas de pregunta del widget (§4.4): textos, plan, sujetos, ocultas.
// Correr: flutter test test/features/home_widget/domain/widget_questions_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_questions.dart';

import '../home_widget_test_helpers.dart';

final _es = realTexts('es');
final _en = realTexts('en');

const _ctx = WidgetQuestionContext(
  tier: SubscriptionTier.gold,
  goalLabel: 'Viaje a Japón',
  hasDrift: true,
  driftTicker: 'ZETA',
  biggestTicker: 'ACME',
  profileRisk: 'moderate',
);

// Verbos de acción / recomendación que no pueden aparecer en una plantilla.
final _action = RegExp(
  r'compr(?!é)|vend|rebalanc|aport|deberías|should i|\b(buy|sell)\b|rebalance|contribute',
  caseSensitive: false,
);

void main() {
  group('WidgetQuestionText.resolve', () {
    test('exact es and en text of each template', () {
      String es(WidgetQuestionTemplate t, Map<String, String> a, [bool h = false]) =>
          WidgetQuestionText.resolve(t, a, h, _es);
      expect(es(WidgetQuestionTemplate.newsWhat, {'ticker': 'ACME'}), '¿Qué pasó con ACME?');
      expect(es(WidgetQuestionTemplate.earningsLast, {'ticker': 'ACME'}), '¿Qué presentó ACME la última vez?');
      expect(es(WidgetQuestionTemplate.moverToday, {'ticker': 'ACME'}), '¿Cómo le fue hoy a ACME en mi cartera?');
      expect(es(WidgetQuestionTemplate.goalProgress, {'goal': 'Casa'}), '¿Cómo voy con Casa?');
      expect(es(WidgetQuestionTemplate.goalProgress, {}, true), '¿Cómo voy con mis metas?');
      expect(es(WidgetQuestionTemplate.profile, {'risk': 'moderate'}), '¿Cómo se compara mi cartera con mi perfil moderado?');
      expect(
        WidgetQuestionText.resolve(WidgetQuestionTemplate.biggest, {'ticker': 'ACME'}, false, _en),
        'How much does my portfolio depend on ACME?',
      );
      expect(
        WidgetQuestionText.resolve(WidgetQuestionTemplate.profile, {}, true, _en),
        'How does my portfolio compare with my investor profile?',
      );
    });

    test('no template matches the action/recommendation verbs', () {
      for (final t in WidgetQuestionTemplate.values) {
        for (final texts in [_es, _en]) {
          for (final hidden in [false, true]) {
            final text = WidgetQuestionText.resolve(
              t,
              {'ticker': 'ACME', 'goal': 'Casa', 'risk': 'moderate'},
              hidden,
              texts,
            );
            expect(_action.hasMatch(text), isFalse, reason: text);
          }
        }
      }
    });

    test('wire round-trips', () {
      for (final t in WidgetQuestionTemplate.values) {
        expect(WidgetQuestionTemplate.fromWire(t.wire), t);
      }
      expect(WidgetQuestionTemplate.fromWire('today'), isNull);
    });
  });

  group('WidgetQuestionsBuilder', () {
    test('every general names a ticker, a goal or "mi/mis" + datum', () {
      final texts = [
        for (final g in WidgetQuestionsBuilder.generals(_ctx, hidden: false))
          g.toRef(_es, hidden: false).text,
      ];
      expect(texts, [
        '¿Cómo voy con Viaje a Japón?',
        '¿Cómo se compara ZETA con mi objetivo?',
        '¿Qué tanto depende mi cartera de ACME?',
        '¿Cómo se compara mi cartera con mi perfil moderado?',
      ]);
    });

    test('no data, no question; no generic fallback', () {
      const empty = WidgetQuestionContext(tier: SubscriptionTier.gold);
      expect(WidgetQuestionsBuilder.generals(empty, hidden: false), isEmpty);
      final r = WidgetQuestionsBuilder.build(
        ctx: empty,
        hidden: false,
        head: null,
        texts: _es,
      );
      expect(r.questions.fallback, isNull);
      expect(r.questions.large, isEmpty);
    });

    test('plan by capability', () {
      WidgetQuestionContext at(SubscriptionTier t) => WidgetQuestionContext(
        tier: t,
        goalLabel: 'Casa',
        biggestTicker: 'ACME',
      );
      List<String> wires(SubscriptionTier t) => [
        for (final g in WidgetQuestionsBuilder.generals(at(t), hidden: false))
          g.template.wire,
      ];
      expect(wires(SubscriptionTier.free), ['biggest']);
      expect(wires(SubscriptionTier.premium), ['goal_progress', 'biggest']);
      expect(WidgetQuestionsBuilder.forEarnings(SubscriptionTier.free, 'A'), isNull);
      expect(WidgetQuestionsBuilder.forEarnings(SubscriptionTier.premium, 'A'), isNull);
      expect(WidgetQuestionsBuilder.forEarnings(SubscriptionTier.gold, 'A'), isNotNull);
      expect(WidgetQuestionsBuilder.forNews(SubscriptionTier.free, 'A'), isNull);
      expect(WidgetQuestionsBuilder.forNews(SubscriptionTier.premium, 'A'), isNotNull);
    });

    test('fallback differs from the head subject; large has no repeats', () {
      final head = WidgetQuestionsBuilder.forBiggest(SubscriptionTier.gold, 'ACME');
      final r = WidgetQuestionsBuilder.build(
        ctx: _ctx,
        hidden: false,
        head: head,
        texts: _es,
      );
      expect(r.questions.fallback!.template, 'goal_progress');
      expect(r.questions.large, hasLength(2));
      expect(r.questions.large.first.template, 'biggest');
      expect(r.questions.large.last.template, 'goal_progress');
      // Una general del mismo sujeto que el head no se repite.
      expect(
        {for (final q in r.questions.large) q.ref},
        hasLength(r.questions.large.length),
      );
    });

    test('hidden: only variants with a hidden text, no ticker or goal', () {
      final r = WidgetQuestionsBuilder.build(
        ctx: _ctx,
        hidden: true,
        head: null,
        texts: _es,
      );
      final all = [r.questions.fallback!, ...r.questions.large];
      for (final q in all) {
        for (final secret in ['ACME', 'ZETA', 'Japón']) {
          expect(q.text, isNot(contains(secret)));
        }
      }
      expect(r.questions.fallback!.text, '¿Cómo voy con mis metas?');
      expect(r.questions.large, hasLength(2));
    });

    test('ref is deterministic, 8 hex, and differs when hidden', () {
      final d = WidgetQuestionsBuilder.forBiggest(SubscriptionTier.gold, 'ACME')!;
      expect(d.ref(hidden: false), d.ref(hidden: false));
      expect(d.ref(hidden: false), matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(d.ref(hidden: false), isNot(d.ref(hidden: true)));
    });
  });
}
