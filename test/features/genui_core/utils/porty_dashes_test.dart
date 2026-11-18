import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/genui_core/utils/porty_dashes.dart';

void main() {
  group('PortyDashes.clean', () {
    test('a dash between two ideas becomes a comma', () {
      expect(
        PortyDashes.clean('Tu cartera subió — sobre todo por Apple.'),
        'Tu cartera subió, sobre todo por Apple.',
      );
      expect(PortyDashes.clean('subió—bastante'), 'subió, bastante');
      expect(PortyDashes.clean('a – b'), 'a, b');
    });

    test('at the start or end of a text it is dropped', () {
      expect(PortyDashes.clean('{"text":"— Hola"}'), '{"text":"Hola"}');
      expect(PortyDashes.clean('{"text":"Hola —"}'), '{"text":"Hola"}');
      expect(PortyDashes.clean('uno\n— dos'), 'uno\ndos');
    });

    test('next to punctuation the punctuation is enough', () {
      expect(PortyDashes.clean('Apple —, Microsoft'), 'Apple, Microsoft');
      expect(PortyDashes.clean('Apple —.'), 'Apple.');
    });

    test('ranges and the rest of the JSON stay as they are', () {
      const json = '{"text":"Esperá 5–10 segundos","pct":"3,5%"}';
      expect(PortyDashes.clean(json), json);
      expect(PortyDashes.clean('3–9 nov'), '3–9 nov');
    });

    test('the cleaned JSON is still valid', () {
      const raw =
          '{"component":"QaAnswerText","text":"Subió — y mucho — esta semana"}';
      expect(
        PortyDashes.clean(raw),
        '{"component":"QaAnswerText","text":"Subió, y mucho, esta semana"}',
      );
    });
  });
}
