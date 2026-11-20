import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/translate/app_language.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/sector_display_name.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/assistant/utils/analysis_prose_check.dart';
import 'package:portfolio_assistant/features/assistant/utils/period_labels.dart';
import 'package:portfolio_assistant/features/assistant/utils/porty_answer_tone.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_draft.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_validator.dart';
import 'package:portfolio_assistant/features/weekly_report/prompts/weekly_report_prompt.dart';

import '../../weekly_report/weekly_report_fixtures.dart';

/// Porty tiene que funcionar igual de bien en inglés: los chequeos que
/// corrigen o recortan respuestas no pueden depender del español.
void main() {
  tearDown(() => AppLanguage.set('es'));

  group('AppLanguage', () {
    test('normalizes any code to es | en', () {
      AppLanguage.set('en_US');
      expect(AppLanguage.code, 'en');
      AppLanguage.set('es-AR');
      expect(AppLanguage.code, 'es');
    });

    test('detects the language of a message; ambiguous → the app', () {
      expect(AppLanguage.detect('How much did my portfolio make this week?'),
          'en');
      expect(AppLanguage.detect('¿Cuánto ganó mi cartera esta semana?'), 'es');
      expect(AppLanguage.detect('Why did NVDA drop today?'), 'en');
      expect(AppLanguage.detect('armá mi compra mensual'), 'es');
      expect(AppLanguage.detect('AAPL', fallback: 'en'), 'en');
      expect(AppLanguage.detect('ok', fallback: 'es'), 'es');
    });
  });

  group('numbers in English format', () {
    const backing = <double>[1234.56, 11.63, 330000, -1.96, 2500];
    List<String> problems(String s) =>
        AnalysisProseCheck.problemsIn(s, backing);

    test('thousands with comma and decimal point are parsed', () {
      final n = AnalysisProseCheck.numbersIn(
        'Worth \$1,234.56, a P/E of 11.6x and \$1,234,567 in sales.',
      );
      expect(n.map((e) => e.value), [1234.56, 11.6, 1234567]);
      expect(n[0].decimals, 2);
    });

    test('real figures written in English are backed (not deleted)', () {
      expect(problems('Your portfolio is worth \$1,234.56 today.'), isEmpty);
      expect(problems('You have \$2,500 invested.'), isEmpty);
      expect(problems('It fell 1.96% this week.'), isEmpty);
      expect(problems('It is worth about 0.33 trillion dollars.'), isEmpty);
      expect(problems('It is worth 330 billion dollars.'), isEmpty);
    });

    test('Spanish formats keep working', () {
      expect(problems('Tu cartera vale \$1.234,56 hoy.'), isEmpty);
      expect(problems('Tenés \$2.500 invertidos.'), isEmpty);
      expect(problems('Vale 3.500 millones.'), hasLength(1));
    });

    test('an invented number in English is still flagged', () {
      expect(problems('Sales grew 42% last year.'), hasLength(1));
      expect(problems('The sector P/E is 15x.'), hasLength(1));
    });

    test('"the last 30 days" is a time span, not a repeated number', () {
      expect(
        AnalysisProseCheck.repeatedNumbers('Over the last 30 days:', [30]),
        0,
      );
    });
  });

  group('advice and valuation in English', () {
    test('imperatives and recommendations are flagged', () {
      expect(AnalysisProseCheck.hasAdvice('You should buy more NVDA.'), isTrue);
      expect(
        AnalysisProseCheck.hasAdvice("It's a good time to buy AAPL."),
        isTrue,
      );
      expect(AnalysisProseCheck.hasAdvice('This is a buying opportunity.'),
          isTrue);
      expect(AnalysisProseCheck.hasAdvice('I recommend selling it.'), isTrue);
    });

    test('descriptions are not advice', () {
      expect(
        AnalysisProseCheck.hasAdvice('Apple makes 30 cents of every dollar.'),
        isFalse,
      );
      expect(
        AnalysisProseCheck.hasAdvice('Investors sold the stock after the '
            'report.'),
        isFalse,
      );
    });

    test('valuation judgments are flagged', () {
      expect(AnalysisProseCheck.hasValuationJudgment('NVDA looks cheap.'),
          isTrue);
      expect(
        AnalysisProseCheck.hasValuationJudgment('The stock is overvalued.'),
        isTrue,
      );
      expect(
        AnalysisProseCheck.hasValuationJudgment('Its P/E is 30.'),
        isFalse,
      );
    });
  });

  group('Porty mood in English', () {
    test('a portfolio loss is detected', () {
      expect(PortyAnswerTone.textShowsLoss('Your portfolio fell 3% this '
          'week.'), isTrue);
      expect(PortyAnswerTone.textShowsLoss('You lost \$40 on TSLA.'), isTrue);
    });

    test('naming a loss without stating it is not a loss', () {
      expect(
        PortyAnswerTone.textShowsLoss('Here is how much you made or lost.'),
        isFalse,
      );
      expect(PortyAnswerTone.textShowsLoss('Your portfolio rose 2%.'), isFalse);
    });
  });

  group('data labels follow the app language', () {
    test('period labels', () {
      expect(PeriodLabels.of('week', language: 'es'), 'últimos 7 días');
      expect(PeriodLabels.of('week', language: 'en'), 'last 7 days');
    });

    test('sector names: Spanish is canonical, English for display', () {
      expect(SectorDisplayName.fromRaw('Technology'), 'Tecnología');
      expect(
        SectorDisplayName.localize('Tecnología', language: 'en'),
        'Technology',
      );
      expect(
        SectorDisplayName.localize('Tecnología', language: 'es'),
        'Tecnología',
      );
      expect(SectorDisplayName.localize('Crypto', language: 'en'), 'Crypto');
    });
  });

  group('turn context', () {
    test('the pinned context says the app language before the JSON', () {
      final en = AssistantOpenAiService.pinnedContextFor({
        PortfolioBrief.appLanguageKey: 'en',
      });
      expect(en, startsWith(PortfolioBrief.label));
      expect(en, contains('App language: ENGLISH'));
      expect(en.indexOf('ENGLISH'), lessThan(en.indexOf('{')));
      final es = AssistantOpenAiService.pinnedContextFor({
        PortfolioBrief.appLanguageKey: 'es',
      });
      expect(es, contains('App language: SPANISH'));
    });
  });

  group('weekly report in English', () {
    final input = fixtureInput();

    test('one prompt per language, same rules', () {
      expect(weeklyReportSystemPromptFor('es'), weeklyReportSystemPrompt);
      expect(weeklyReportSystemPromptFor('en'), weeklyReportSystemPromptEn);
      expect(weeklyReportSystemPromptEn, isNot(contains('voseo')));
      expect(weeklyReportSystemPromptEn, contains('FORBIDDEN'));
    });

    test('a good English draft passes, with English headlines allowed', () {
      final r = WeeklyReportValidator.review(
        const WeeklyReportDraft(
          reading: 'A quiet week: you were up a little, more than the market.',
          movers: [
            DraftMover(
              ticker: 'AAPL',
              why: 'It coincided with strong preorders for the new iPhone.',
              newsId: 'n1',
            ),
          ],
          headlines: [],
          investors: [],
          learn: null,
        ),
        input,
        language: 'en',
      );
      expect(
        r.issues.where((i) => i.startsWith('reading') || i.contains('AAPL')),
        isEmpty,
      );
      expect(r.draft.reading, isNotNull);
      expect(r.draft.movers, hasLength(1));
    });

    test('English causation, jargon and advice are caught, in English', () {
      final r = WeeklyReportValidator.review(
        const WeeklyReportDraft(
          reading: 'Your portfolio is in positive territory.',
          movers: [
            DraftMover(
              ticker: 'AAPL',
              why: 'It rose because of strong iPhone preorders.',
              newsId: 'n1',
            ),
            DraftMover(
              ticker: 'MSFT',
              why: 'Bearish sentiment hit it; you should sell it.',
              newsId: null,
            ),
          ],
          headlines: [],
          investors: [],
          learn: null,
        ),
        input,
        language: 'en',
      );
      expect(r.draft.reading, isNull);
      expect(r.draft.movers, isEmpty);
      final all = r.issues.join('\n');
      expect(all, contains('states a cause'));
      expect(all, contains('uses jargon'));
      expect(all, contains('gives buy or sell advice'));
      expect(all, contains('empty phrase'));
    });
  });
}
