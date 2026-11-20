// Callback `loadDailyBrief` que el chat inyecta: el brief de hoy, sin `v` ni
// `audio`; nada si no hay brief de hoy. Correr:
// flutter test test/features/daily_brief/daily_brief_chat_loader_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_chat_loader.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_numbers.dart';

import 'fakes/daily_brief_fakes.dart';

void main() {
  DailyBrief brief() => DailyBrief.compose(
    day: briefDay,
    lang: 'es',
    now: briefNow(),
    numbers: DailyBriefNumbers.compute(
      history: history(),
      lots: lots,
      candlesByTicker: candles,
      now: briefNow(),
    ),
    bundle: DailyBriefBundle.empty,
    variant: DailyBriefVariant.numbers,
  );

  test('today brief goes out without version and audio', () {
    final json = dailyBriefForChat(brief(), now: briefNow())!;
    expect(json['day'], briefDay);
    expect(json.containsKey('v'), isFalse);
    expect(json.containsKey('audio'), isFalse);
    expect(json['numbers'], isA<Map>());
  });

  test('no brief or another day: null (not_ready)', () {
    expect(dailyBriefForChat(null), isNull);
    expect(dailyBriefForChat(brief(), now: DateTime(2026, 11, 27, 8)), isNull);
  });
}
