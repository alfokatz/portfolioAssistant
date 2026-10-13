import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_name_fix.dart';

void main() {
  group('PortyNameFix: dictated name', () {
    final fixed = {
      'Por ti cuánto tengo que juntar para una computadora':
          'Porty cuánto tengo que juntar para una computadora',
      'por ti, ¿cómo va mi meta?': 'Porty, ¿cómo va mi meta?',
      '¿Por ti, cuánto gané esta semana?': '¿Porty, cuánto gané esta semana?',
      'Hola por ti, ¿cómo estás?': 'Hola Porty, ¿cómo estás?',
      'Che por tí qué pasó con Apple': 'Che Porty qué pasó con Apple',
      'Buen día por ti': 'Buen día Porty',
      'Gracias. Por ti, otra cosa': 'Gracias. Porty, otra cosa',
      '¿Cuánto tengo en bonos, por ti?': '¿Cuánto tengo en bonos, Porty?',
      'Mirá, por ti, quiero comprar EWZ': 'Mirá, Porty, quiero comprar EWZ',
      'gracias por ti': 'gracias Porty',
      'Porti cómo va mi cartera': 'Porty cómo va mi cartera',
      'hola portí': 'hola Porty',
      'Le pregunté a porty ayer': 'Le pregunté a Porty ayer',
    };
    for (final MapEntry(key: heard, value: expected) in fixed.entries) {
      test('"$heard"', () => expect(PortyNameFix.fix(heard), expected));
    }

    // "Por ti" con su sentido de siempre queda igual.
    for (final text in [
      'Lo hice por ti y por mi familia',
      'Esto lo compré por ti',
      'Quiero ahorrar por tiempo indeterminado',
      'Gracias por tirarme la idea',
      'portfolio de largo plazo',
      'el aporte mensual',
    ]) {
      test('keeps "$text"', () => expect(PortyNameFix.fix(text), text));
    }
  });
}
