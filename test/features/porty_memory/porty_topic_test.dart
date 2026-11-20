// Un tema de charla (porty_topics): leer la fila y cómo va en el brief.
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/porty_topic.dart';
import 'package:portfolio_assistant/features/porty_memory/providers/porty_topics_provider.dart';

void main() {
  group('PortyTopic', () {
    test('reads the row; a broken row is skipped', () {
      final t =
          PortyTopic.fromRow({
            'ticker': 'AMZN',
            'question': '¿Cómo viene?',
            'price_at': '182.5',
            'held': false,
            'last_asked_at': '2026-10-14T13:00:00Z',
            'times': 3,
          })!;
      expect(t.priceAt, 182.5);
      expect(t.times, 3);
      expect(PortyTopic.fromRow({'ticker': 'AMZN'}), isNull);
    });

    test('in the brief: date, days ago, price then; held and times only if '
        'they say something', () {
      final t = PortyTopic(
        ticker: 'AMZN',
        question: 'q',
        lastAskedAt: DateTime(2026, 10, 14, 10),
        priceAt: 182.5,
      );
      expect(t.toBrief(DateTime(2026, 10, 24, 10)), {
        'ticker': 'AMZN',
        'asked': '2026-10-14',
        'days_ago': 10,
        'price_then': 182.5,
      });
    });

    test('recent: only the last 30 days', () {
      final now = DateTime(2026, 10, 24);
      final state = PortyTopicsState(
        topics: [
          PortyTopic(
            ticker: 'A',
            question: 'q',
            lastAskedAt: DateTime(2026, 10, 20),
          ),
          PortyTopic(
            ticker: 'B',
            question: 'q',
            lastAskedAt: DateTime(2026, 9, 1),
          ),
        ],
        loaded: true,
      );
      expect([for (final t in state.recent(now)) t.ticker], ['A']);
    });
  });
}
