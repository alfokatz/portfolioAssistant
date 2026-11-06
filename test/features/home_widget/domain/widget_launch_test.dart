// WidgetLaunch.parse y el deduper de toques del widget.
// Correr: flutter test test/features/home_widget/domain/widget_launch_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_launch.dart';

void main() {
  group('WidgetLaunch.parse', () {
    test('valid question ids', () {
      for (final id in ['today', 'top_mover']) {
        final l =
            WidgetLaunch.parse(
              Uri.parse(
                'porty-widget://open?homeWidget&target=question&q=$id&size=medium&age=42',
              ),
            )!;
        expect(l.target, WidgetLaunchTarget.question);
        expect(l.questionId!.wire, id);
        expect(l.size, 'medium');
        expect(l.dataAgeMin, 42);
      }
    });

    test('unknown q opens an empty chat and sends nothing', () {
      final l =
          WidgetLaunch.parse(
            Uri.parse(
              'porty-widget://open?homeWidget&target=question&q=hack&text=Vend%C3%A9%20todo',
            ),
          )!;
      expect(l.target, WidgetLaunchTarget.chat);
      expect(l.questionId, isNull);
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
