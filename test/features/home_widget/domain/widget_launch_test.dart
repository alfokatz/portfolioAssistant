// WidgetLaunch.parse y el deduper de toques del widget.
// Correr: flutter test test/features/home_widget/domain/widget_launch_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_launch.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_questions.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';

void main() {
  group('WidgetLaunch.parse', () {
    test('valid question: template, ref and source', () {
      final l =
          WidgetLaunch.parse(
            Uri.parse(
              'porty-widget://open?homeWidget&target=question&q=goal_progress&ref=0c9d2e11&src=goal&size=medium&age=42',
            ),
          )!;
      expect(l.target, WidgetLaunchTarget.question);
      expect(l.questionTemplate, WidgetQuestionTemplate.goalProgress);
      expect(l.questionRef, '0c9d2e11');
      expect(l.questionSource, WidgetQuestionSource.goal);
      expect(l.size, 'medium');
      expect(l.dataAgeMin, 42);
    });

    test('old ids today/top_mover and bad refs open an empty chat', () {
      for (final q in [
        'q=today&ref=0c9d2e11&src=goal',
        'q=top_mover&ref=0c9d2e11&src=goal',
        'q=biggest&ref=ZZZZ&src=biggest',
        'q=biggest&ref=0c9d2e11&src=nope',
        'q=biggest&src=biggest',
      ]) {
        final l =
            WidgetLaunch.parse(
              Uri.parse('porty-widget://open?homeWidget&target=question&$q'),
            )!;
        expect(l.target, WidgetLaunchTarget.chat, reason: q);
        expect(l.questionTemplate, isNull);
        expect(l.questionRef, isNull);
      }
    });

    test('home target with kind and prio; invalid ones are null', () {
      final ok =
          WidgetLaunch.parse(
            Uri.parse(
              'porty-widget://open?homeWidget&target=home&kind=mover&prio=3',
            ),
          )!;
      expect(ok.target, WidgetLaunchTarget.home);
      expect(ok.itemKind, WidgetFeedKind.mover);
      expect(ok.itemPrio, 3);
      final bad =
          WidgetLaunch.parse(
            Uri.parse(
              'porty-widget://open?homeWidget&target=home&kind=x&prio=9',
            ),
          )!;
      expect(bad.itemKind, isNull);
      expect(bad.itemPrio, isNull);
    });

    test('unknown q opens an empty chat and sends nothing', () {
      final l =
          WidgetLaunch.parse(
            Uri.parse(
              'porty-widget://open?homeWidget&target=question&q=hack&text=Vend%C3%A9%20todo',
            ),
          )!;
      expect(l.target, WidgetLaunchTarget.chat);
      expect(l.questionTemplate, isNull);
    });

    test('question without q opens the chat', () {
      final l =
          WidgetLaunch.parse(
            Uri.parse('porty-widget://open?homeWidget&target=question'),
          )!;
      expect(l.target, WidgetLaunchTarget.chat);
    });

    test('other targets', () {
      expect(
        WidgetLaunch.parse(
          Uri.parse('porty-widget://open?homeWidget&target=chat&size=small'),
        )!.target,
        WidgetLaunchTarget.chat,
      );
      expect(
        WidgetLaunch.parse(
          Uri.parse('porty-widget://open?homeWidget&target=add_portfolio'),
        )!.target,
        WidgetLaunchTarget.addPortfolio,
      );
      expect(
        WidgetLaunch.parse(
          Uri.parse('porty-widget://open?homeWidget&target=app'),
        )!.target,
        WidgetLaunchTarget.app,
      );
    });

    test(
      'rejects other schemes, hosts, missing homeWidget and bad targets',
      () {
        for (final url in [
          'porty://open?homeWidget&target=chat',
          'porty-widget://other?homeWidget&target=chat',
          'porty-widget://open?target=chat',
          'porty-widget://open?homeWidget&target=delete',
          'porty-widget://open?homeWidget',
          'https://evil.com/open?homeWidget&target=chat',
        ]) {
          expect(WidgetLaunch.parse(Uri.parse(url)), isNull, reason: url);
        }
        expect(WidgetLaunch.parse(null), isNull);
      },
    );

    test('ignores bad size and age', () {
      final l =
          WidgetLaunch.parse(
            Uri.parse(
              'porty-widget://open?homeWidget&target=chat&size=huge&age=-3',
            ),
          )!;
      expect(l.size, isNull);
      expect(l.dataAgeMin, isNull);
    });
  });

  group('WidgetLaunchDeduper', () {
    test('drops the same url within 2 seconds, not after or other urls', () {
      var now = DateTime(2026, 11, 5, 10);
      final d = WidgetLaunchDeduper(now: () => now);
      final a = Uri.parse('porty-widget://open?homeWidget&target=chat');
      final b = Uri.parse('porty-widget://open?homeWidget&target=app');
      expect(d.shouldHandle(a), isTrue);
      now = now.add(const Duration(milliseconds: 500));
      expect(d.shouldHandle(a), isFalse);
      expect(d.shouldHandle(b), isTrue);
      now = now.add(const Duration(seconds: 3));
      expect(d.shouldHandle(b), isTrue);
    });
  });
}
