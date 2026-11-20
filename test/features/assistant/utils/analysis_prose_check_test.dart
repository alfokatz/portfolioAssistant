import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/utils/analysis_prose_check.dart';

void main() {
  // Datos reales de BAC de get_fundamentals (market cap en millones).
  const backing = <double>[
    11.63,
    30.16,
    11.13,
    3.23,
    1.2,
    330000,
    -1.96,
    2026,
    10,
    20,
  ];

  List<String> problems(String s) => AnalysisProseCheck.problemsIn(s, backing);

  group('numbers', () {
    test('parses Spanish formats: decimals, thousands, %, x, T/B', () {
      final n = AnalysisProseCheck.numbersIn(
        'P/E 11,6x, margen 30,16 %, 1.234,5 dólares y vale \$3,78T',
      );
      expect(n.map((e) => e.value), [11.6, 30.16, 1234.5, 3.78]);
      expect(n[0].decimals, 1);
      expect(n[3].scale, 'T');
      expect(n[1].percent, isTrue);
    });

    test('a rounded citation of a real value is backed', () {
      expect(problems('Su P/E es de 11,6x.'), isEmpty);
      expect(problems('Gana 30 de cada 100 dólares que vende.'), isEmpty);
      expect(problems('Bajó 1,96% en la semana.'), isEmpty);
      expect(problems('Vale \$0,33T en bolsa.'), isEmpty);
    });

    test('an invented number is flagged', () {
      expect(problems('El P/E del sector es de 15x.'), hasLength(1));
      expect(problems('Creció 42% en ventas.'), hasLength(1));
    });

    test('Spanish scale words: "billones" is 10^12 (long scale)', () {
      // market_capitalization = 330000 millones = 0,33 billones.
      expect(problems('Vale unos 0,33 billones de dólares.'), isEmpty);
      expect(problems('Vale 330 mil millones de dólares.'), isEmpty);
      // El error real visto en evals: 3.500 millones por 3,5 billones.
      expect(problems('Vale 3.500 millones.'), hasLength(1));
    });

    test('plain-language framing numbers are allowed', () {
      expect(
        problems('Superó lo esperado en 3 de los últimos 4 trimestres.'),
        isEmpty,
      );
      expect(problems('Está lejos de su máximo de 52 semanas.'), isEmpty);
    });
  });

  group('advice', () {
    test('imperatives and recommendations are flagged', () {
      expect(
        AnalysisProseCheck.hasAdvice('Comprá ahora que está barata.'),
        isTrue,
      );
      expect(
        AnalysisProseCheck.hasAdvice('Es buen momento para entrar.'),
        isTrue,
      );
      expect(AnalysisProseCheck.hasAdvice('Te conviene vender.'), isTrue);
      expect(AnalysisProseCheck.hasAdvice('Deberías comprar más.'), isTrue);
    });

    test('descriptions that use the same verbs are not advice', () {
      expect(
        AnalysisProseCheck.hasAdvice('Gana 30 de cada 100 dólares que vende.'),
        isFalse,
      );
      expect(
        AnalysisProseCheck.hasAdvice('Anunció la compra de una fintech.'),
        isFalse,
      );
    });
  });

  test('cheap/expensive judgments without a comparable are flagged', () {
    expect(AnalysisProseCheck.hasValuationJudgment('La acción está barata.'), isTrue);
    expect(AnalysisProseCheck.hasValuationJudgment('Tiene un P/E alto.'), isTrue);
    expect(
      AnalysisProseCheck.hasValuationJudgment('Pagás 11,6 veces lo que gana.'),
      isFalse,
    );
  });

  test('clean drops only the offending sentences', () {
    expect(
      AnalysisProseCheck.clean(
        'Es un banco grande. Su P/E es 11,6x. El del sector es 15x.',
        backing,
      ),
      'Es un banco grande. Su P/E es 11,6x.',
    );
  });

  test('repeatedNumbers counts card numbers echoed by the intro', () {
    expect(
      AnalysisProseCheck.repeatedNumbers(
        'Tiene un P/E de 11,63x y un margen neto de 30,16%.',
        backing,
      ),
      2,
    );
    expect(
      AnalysisProseCheck.repeatedNumbers(
        'Este es el análisis de BAC.',
        backing,
      ),
      0,
    );
  });
}
