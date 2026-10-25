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

bool _loss(List<(String, Map<String, Object?>)> components) =>
    PortyAnswerTone.showsLoss(_surface(components));

void main() {
  test('a neutral or positive answer is not bad news', () {
    expect(PortyAnswerTone.showsLoss(null), isFalse);
    expect(
      _loss([
        ('QaAnswerText', {'text': 'Tu cartera vale 600 dólares, +2,1 %.'}),
        ('QaPeriodChange', {'changeAbs': 12.5, 'changePct': 2.1}),
      ]),
      isFalse,
    );
  });

  test('the whole portfolio down is bad news', () {
    expect(
      _loss([
        ('QaPeriodChange', {'changeAbs': -40, 'changePct': -3.2}),
      ]),
      isTrue,
    );
    expect(
      _loss([
        ('QaPositionsSnapshot', {'totalValue': 900, 'pnlAbs': -100}),
      ]),
      isTrue,
    );
    expect(
      _loss([
        ('QaPnLBreakdown', {'gainLoss': -12, 'gainLossPercent': -1.1}),
      ]),
      isTrue,
    );
    expect(
      _loss([
        ('QaClosedPositionList', {'totalPnlAbs': -30}),
      ]),
      isTrue,
    );
  });

  test('one position in red, or a stock down today, is not', () {
    expect(
      _loss([
        (
          'QaPositionsSnapshot',
          {
            'pnlAbs': 250,
            'positions': [
              {'ticker': 'NVDA', 'pnlPct': 12.4},
              {'ticker': 'KO', 'pnlPct': -3.1},
            ],
          },
        ),
        (
          'QaTopMovers',
          {
            'items': [
              {'ticker': 'AAPL', 'dayChangePct': -0.4},
            ],
          },
        ),
        ('QaTickerSnapshot', {'ticker': 'MSFT', 'changePct': -1.2}),
        (
          'QaTipBanner',
          {'message': 'Ojo con la concentración', 'warning': true},
        ),
        ('QaAnswerText', {'text': 'NVDA cayó 2 % hoy, el resto subió.'}),
      ]),
      isFalse,
    );
  });

  test('text saying the portfolio dropped, or that you lost, is', () {
    for (final text in [
      'Tu cartera bajó esta semana.',
      'El portfolio cayó 1,5 % en el mes.',
      'Tus inversiones están en rojo.',
      'Perdiste 40 dólares.',
      'Estás perdiendo un 2 % en el año.',
    ]) {
      expect(PortyAnswerTone.textShowsLoss(text), isTrue, reason: text);
    }
    for (final text in [
      'Tu cartera subió 3 % en el mes.',
      'AAPL cayó, pero tu cartera subió.',
      'Si la cartera baja, conviene revisar.',
    ]) {
      expect(PortyAnswerTone.textShowsLoss(text), isFalse, reason: text);
    }
  });

  test('the cards decide over the text (bug 2026-10-06: sad Porty on a '
      'portfolio in green)', () {
    expect(
      _loss([
        (
          'QaAnswerText',
          {
            'text':
                'Esta es la foto actual de tus posiciones: cuánto valen hoy y '
                'cuánto ganaste o perdiste desde la compra.',
          },
        ),
        ('QaPositionsSnapshot', {'totalValue': 2109, 'pnlAbs': 600}),
      ]),
      isFalse,
    );
    expect(
      _loss([
        ('QaAnswerText', {'text': 'Tu cartera subió.'}),
        ('QaPeriodChange', {'changeAbs': -40, 'changePct': -3.2}),
      ]),
      isTrue,
      reason: 'el número negativo manda aunque el texto diga otra cosa',
    );
  });

  test('naming a loss without claiming it is not bad news', () {
    for (final text in [
      'Mirá cuánto ganaste o perdiste desde la compra.',
      'Te muestro si perdiste o ganaste en el mes.',
      'No perdiste nada esta semana.',
    ]) {
      expect(PortyAnswerTone.textShowsLoss(text), isFalse, reason: text);
    }
  });
}
