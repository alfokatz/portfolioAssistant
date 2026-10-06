import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/utils/porty_answer_tone.dart';

SurfaceDefinition _surface(List<(String, Map<String, Object?>)> components) =>
    SurfaceDefinition(
      surfaceId: 's',
      components: {
        for (final (i, (type, props)) in components.indexed)
          'c$i': Component(id: 'c$i', type: type, properties: props),
      },
    );

void main() {
  test('a plain, neutral or positive answer is not bad news', () {
    expect(PortyAnswerTone.showsLoss(null), isFalse);
    expect(
      PortyAnswerTone.showsLoss(
        _surface([
          ('QaAnswerText', {'text': 'Tu cartera vale 600 dólares, +2,1 %.'}),
          (
            'QaPeriodChange',
            {'periodLabel': 'Semana', 'changeAbs': 12.5, 'changePct': 2.1},
          ),
          ('QaTipBanner', {'message': 'Diversificá', 'warning': false}),
        ]),
      ),
      isFalse,
    );
  });

  test('any negative change in the cards is bad news', () {
    expect(
      PortyAnswerTone.showsLoss(
        _surface([
          ('QaPeriodChange', {'changeAbs': -40, 'changePct': -3.2}),
        ]),
      ),
      isTrue,
    );
    // Anidado en una lista (movers, posiciones).
    expect(
      PortyAnswerTone.showsLoss(
        _surface([
          (
            'QaTopMovers',
            {
              'items': [
                {'ticker': 'NVDA', 'dayChangePct': 1.2},
                {'ticker': 'AAPL', 'dayChangePct': -0.4},
              ],
            },
          ),
        ]),
      ),
      isTrue,
    );
    // Un número negativo que no es una variación no cuenta.
    expect(
      PortyAnswerTone.showsLoss(
        _surface([
          ('QaMetricStrip', {'peRatio': -12}),
        ]),
      ),
      isFalse,
    );
  });

  test('a warning tip or text about a drop is bad news', () {
    expect(
      PortyAnswerTone.showsLoss(
        _surface([
          ('QaTipBanner', {'message': 'Ojo', 'warning': true}),
        ]),
      ),
      isTrue,
    );
    for (final text in [
      'Tu cartera bajó esta semana.',
      'NVDA cayó fuerte hoy.',
      'Perdiste 40 dólares.',
      'La semana cerró en −1,5 %.',
      'Quedó en (-0.8%).',
      'Tu cartera está en rojo.',
    ]) {
      expect(PortyAnswerTone.textShowsLoss(text), isTrue, reason: text);
    }
    expect(PortyAnswerTone.textShowsLoss('Subió 3 % en el mes.'), isFalse);
  });
}
